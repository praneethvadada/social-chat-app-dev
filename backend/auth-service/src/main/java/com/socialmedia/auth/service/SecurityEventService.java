package com.socialmedia.auth.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.socialmedia.auth.client.SecurityPushRelayClient;
import com.socialmedia.auth.dto.SecurityEventResponse;
import com.socialmedia.auth.entity.Device;
import com.socialmedia.auth.entity.SecurityEvent;
import com.socialmedia.auth.entity.User;
import com.socialmedia.auth.repository.DeviceRepository;
import com.socialmedia.auth.repository.SecurityEventRepository;
import com.socialmedia.auth.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Append-only audit trail (SecurityEvent entity). Never pass a map
 * containing a password, OTP, or token in `metadata` — see the entity's
 * own doc comment. Recording is best-effort: a failure here must never
 * block the auth flow that triggered it.
 *
 * Phase 9: also the single dispatch point for security-alert emails (spec
 * §29's list) — every call site that already calls record() automatically
 * gets email coverage for free, rather than needing a second call added at
 * each of the ~8 scattered call sites across AuthService/
 * DeviceSessionService/ActiveWebSessionService/TwoFactorAuthService/
 * MobileStorageService. LOGIN and LOGOUT are deliberately excluded (too
 * routine to alert on every time - the spec's own "New login" example maps
 * to NEW_DEVICE, the first-time-seen case, not every login).
 */
@Service
public class SecurityEventService {

    private static final Logger logger = LoggerFactory.getLogger(SecurityEventService.class);

    private static final Set<SecurityEvent.EventType> EMAIL_NOTIFIED_TYPES = EnumSet.of(
            SecurityEvent.EventType.NEW_DEVICE,
            SecurityEvent.EventType.PASSWORD_CHANGED,
            SecurityEvent.EventType.EMAIL_CHANGED,
            SecurityEvent.EventType.PHONE_CHANGED,
            SecurityEvent.EventType.TWO_FA_ENABLED,
            SecurityEvent.EventType.TWO_FA_DISABLED,
            SecurityEvent.EventType.TWO_FA_METHOD_CHANGED,
            SecurityEvent.EventType.SESSION_REVOKED,
            SecurityEvent.EventType.WEB_SESSION_REPLACED,
            SecurityEvent.EventType.LOCAL_STORAGE_DEVICE_CHANGED
    );

    private static final Map<SecurityEvent.EventType, String> EMAIL_TITLES = new EnumMap<>(SecurityEvent.EventType.class);
    private static final Map<SecurityEvent.EventType, String> EMAIL_MESSAGES = new EnumMap<>(SecurityEvent.EventType.class);
    static {
        EMAIL_TITLES.put(SecurityEvent.EventType.NEW_DEVICE, "New device login");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.NEW_DEVICE, "We noticed a sign-in to your account from a device we haven't seen before.");

        EMAIL_TITLES.put(SecurityEvent.EventType.PASSWORD_CHANGED, "Your password was changed");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.PASSWORD_CHANGED, "Your account password was just changed.");

        EMAIL_TITLES.put(SecurityEvent.EventType.EMAIL_CHANGED, "Your account email was updated");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.EMAIL_CHANGED, "An email address was just added or changed on your account.");

        EMAIL_TITLES.put(SecurityEvent.EventType.PHONE_CHANGED, "Your account phone number was updated");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.PHONE_CHANGED, "A phone number was just added or changed on your account.");

        EMAIL_TITLES.put(SecurityEvent.EventType.TWO_FA_ENABLED, "Two-factor authentication enabled");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.TWO_FA_ENABLED, "Two-factor authentication was just turned on for your account.");

        EMAIL_TITLES.put(SecurityEvent.EventType.TWO_FA_DISABLED, "Two-factor authentication disabled");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.TWO_FA_DISABLED, "Two-factor authentication was just turned off for your account.");

        EMAIL_TITLES.put(SecurityEvent.EventType.TWO_FA_METHOD_CHANGED, "Two-factor authentication method changed");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.TWO_FA_METHOD_CHANGED, "Your two-factor authentication method was just changed.");

        EMAIL_TITLES.put(SecurityEvent.EventType.SESSION_REVOKED, "A device was logged out");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.SESSION_REVOKED, "One of your devices/sessions was just logged out remotely.");

        EMAIL_TITLES.put(SecurityEvent.EventType.WEB_SESSION_REPLACED, "New sign-in from a web browser");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.WEB_SESSION_REPLACED, "Your account was just accessed from a new web browser, which signed out your previous web session (only one web session can be active at a time).");

        EMAIL_TITLES.put(SecurityEvent.EventType.LOCAL_STORAGE_DEVICE_CHANGED, "Chat storage device changed");
        EMAIL_MESSAGES.put(SecurityEvent.EventType.LOCAL_STORAGE_DEVICE_CHANGED, "The phone that saves your chats locally was just changed.");
    }

    /**
     * Post-Phase-10, user-requested: push (not email) notifications for
     * EVERY login attempt — successful or not, on any platform (web or
     * mobile) — deliberately a DIFFERENT (wider) set than
     * EMAIL_NOTIFIED_TYPES above, which still excludes plain LOGIN to avoid
     * email spam. The user explicitly asked for push coverage broader than
     * the existing email scope, so this is intentionally its own set rather
     * than folding LOGIN into EMAIL_NOTIFIED_TYPES (which would change
     * already-shipped, unrelated email behavior nobody asked to change).
     *
     * Known limitation: delivered via the existing single-token-per-user
     * FCM mechanism (see SecurityPushRelayClient's own doc comment) — reaches
     * whichever mobile device most recently synced its push token, not
     * literally every mobile device on the account.
     */
    private static final Set<SecurityEvent.EventType> PUSH_NOTIFIED_TYPES = EnumSet.of(
            SecurityEvent.EventType.LOGIN,
            SecurityEvent.EventType.LOGIN_FAILED
    );

    private static final Map<SecurityEvent.EventType, String> PUSH_TITLES = new EnumMap<>(SecurityEvent.EventType.class);
    private static final Map<SecurityEvent.EventType, String> PUSH_MESSAGES = new EnumMap<>(SecurityEvent.EventType.class);
    static {
        PUSH_TITLES.put(SecurityEvent.EventType.LOGIN, "New sign-in to your account");
        PUSH_MESSAGES.put(SecurityEvent.EventType.LOGIN, "Your account was just signed into.");

        PUSH_TITLES.put(SecurityEvent.EventType.LOGIN_FAILED, "Failed sign-in attempt");
        PUSH_MESSAGES.put(SecurityEvent.EventType.LOGIN_FAILED, "Someone just tried to sign into your account with the wrong password.");
    }

    private final SecurityEventRepository securityEventRepository;
    private final DeviceRepository deviceRepository;
    private final UserRepository userRepository;
    private final EmailService emailService;
    private final SecurityPushRelayClient pushRelayClient;
    private final ObjectMapper objectMapper;

    public SecurityEventService(SecurityEventRepository securityEventRepository,
                                 DeviceRepository deviceRepository,
                                 UserRepository userRepository,
                                 EmailService emailService,
                                 SecurityPushRelayClient pushRelayClient,
                                 ObjectMapper objectMapper) {
        this.securityEventRepository = securityEventRepository;
        this.deviceRepository = deviceRepository;
        this.userRepository = userRepository;
        this.emailService = emailService;
        this.pushRelayClient = pushRelayClient;
        this.objectMapper = objectMapper;
    }

    public void record(Long userId, SecurityEvent.EventType type, Long deviceId, Long sessionId,
                        String ipAddress, String userAgent, Map<String, Object> metadata) {
        try {
            SecurityEvent event = new SecurityEvent();
            event.setUserId(userId);
            event.setEventType(type.name());
            event.setDeviceId(deviceId);
            event.setSessionId(sessionId);
            event.setIpAddress(ipAddress);
            event.setUserAgent(userAgent);
            if (metadata != null && !metadata.isEmpty()) {
                event.setMetadata(objectMapper.writeValueAsString(metadata));
            }
            event.setCreatedAt(LocalDateTime.now());
            securityEventRepository.save(event);
        } catch (Exception e) {
            logger.warn("Failed to record security event {} for user {}: {}", type, userId, e.getMessage());
        }

        // Independent of whether the audit row above actually saved — a DB
        // hiccup on the audit trail shouldn't also suppress the user-facing
        // notice, and vice versa.
        if (EMAIL_NOTIFIED_TYPES.contains(type)) {
            sendAlertEmail(userId, type, deviceId, metadata);
        }
        if (PUSH_NOTIFIED_TYPES.contains(type)) {
            pushRelayClient.sendSecurityAlert(userId, PUSH_TITLES.get(type), PUSH_MESSAGES.get(type));
        }
    }

    private void sendAlertEmail(Long userId, SecurityEvent.EventType type, Long deviceId, Map<String, Object> metadata) {
        try {
            User user = userRepository.findById(userId).orElse(null);
            // Phone-only accounts have no email to notify — a real gap (spec
            // §29 only covers email notifications, no SMS equivalent exists),
            // not something silently worked around here.
            if (user == null || user.getEmail() == null || user.getEmail().isBlank()) {
                return;
            }

            Map<String, String> details = new LinkedHashMap<>();
            if (deviceId != null) {
                deviceRepository.findById(deviceId).ifPresent(d -> {
                    String label = (d.getDeviceModel() != null && !d.getDeviceModel().isBlank()) ? d.getDeviceModel()
                            : (d.getOsName() != null && !d.getOsName().isBlank()) ? d.getOsName() : d.getPlatform();
                    if (label != null) details.put("Device", label);
                    if (d.getPlatform() != null) details.put("Platform", d.getPlatform());
                });
            }
            if (metadata != null) {
                for (Map.Entry<String, Object> entry : metadata.entrySet()) {
                    details.put(humanizeKey(entry.getKey()), String.valueOf(entry.getValue()));
                }
            }

            emailService.sendSecurityAlertEmail(
                    user.getEmail(), user.getUsername(),
                    EMAIL_TITLES.get(type), EMAIL_MESSAGES.get(type), details);
        } catch (Exception e) {
            logger.warn("Failed to send security alert email for user {} type {}: {}", userId, type, e.getMessage());
        }
    }

    /** e.g. "fromDeviceId" -> "From Device Id" — good enough for an email details row, not worth a real word-boundary library for this. */
    private String humanizeKey(String key) {
        if (key == null || key.isEmpty()) return key;
        StringBuilder result = new StringBuilder();
        result.append(Character.toUpperCase(key.charAt(0)));
        for (int i = 1; i < key.length(); i++) {
            char c = key.charAt(i);
            if (Character.isUpperCase(c)) result.append(' ');
            result.append(c);
        }
        return result.toString();
    }

    /** Phase 8: GET /security/events — this user's own audit trail, newest first. */
    @Transactional(readOnly = true)
    public Page<SecurityEventResponse> list(Long userId, Pageable pageable) {
        return securityEventRepository.findByUserIdOrderByCreatedAtDesc(userId, pageable).map(this::toResponse);
    }

    private SecurityEventResponse toResponse(SecurityEvent event) {
        SecurityEventResponse dto = new SecurityEventResponse();
        dto.setId(event.getId());
        dto.setEventType(event.getEventType());
        dto.setCreatedAt(event.getCreatedAt());
        dto.setIpAddress(event.getIpAddress());

        if (event.getMetadata() != null) {
            try {
                dto.setMetadata(objectMapper.readValue(event.getMetadata(), new TypeReference<Map<String, Object>>() {}));
            } catch (Exception e) {
                logger.warn("Failed to parse metadata for security event {}: {}", event.getId(), e.getMessage());
            }
        }

        if (event.getDeviceId() != null) {
            Optional<Device> device = deviceRepository.findById(event.getDeviceId());
            device.ifPresent(d -> {
                dto.setPlatform(d.getPlatform());
                dto.setOsName(d.getOsName());
                dto.setBrowserName(d.getBrowserName());
                dto.setDeviceModel(d.getDeviceModel());
            });
        }

        return dto;
    }
}
