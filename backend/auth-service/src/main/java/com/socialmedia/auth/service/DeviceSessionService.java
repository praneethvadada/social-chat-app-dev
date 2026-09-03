package com.socialmedia.auth.service;

import com.socialmedia.auth.dto.DeviceInfoRequest;
import com.socialmedia.auth.dto.DeviceResponse;
import com.socialmedia.auth.entity.Device;
import com.socialmedia.auth.entity.SecurityEvent;
import com.socialmedia.auth.entity.UserSession;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.repository.DeviceRepository;
import com.socialmedia.auth.repository.UserSessionRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Owns the devices/user_sessions tables — device identity is separate from
 * a login session (a device keeps the same row across many logins), and a
 * session is separate from the JWT itself (the JWT's "sid" claim just
 * points at a session row, letting it be revoked before its natural
 * expiry). See the Phase 1 architecture plan for the full model.
 *
 * Design choice made during planning: a direct DB lookup (not a Redis
 * cache) backs the per-request revocation check in JwtAuthenticationFilter,
 * matching this codebase's existing pattern of not depending on Redis being
 * reliably available (see IpRateLimiter's and AuthService.refreshToken's
 * own comments to that effect) — a session_token unique-index point lookup
 * is fast enough on its own.
 */
@Service
public class DeviceSessionService {

    /** How stale last_active_at must be before a request bothers updating it — avoids a write on every single API call. */
    private static final long LAST_ACTIVE_THROTTLE_SECONDS = 60;

    public enum SessionCheckResult {
        ACTIVE,
        REVOKED,
        /** No "sid" claim on the token at all — predates this feature; treated as an untracked, implicitly-trusted legacy session. */
        NOT_TRACKED
    }

    private final DeviceRepository deviceRepository;
    private final UserSessionRepository userSessionRepository;
    private final SecurityEventService securityEventService;

    public DeviceSessionService(DeviceRepository deviceRepository,
                                 UserSessionRepository userSessionRepository,
                                 SecurityEventService securityEventService) {
        this.deviceRepository = deviceRepository;
        this.userSessionRepository = userSessionRepository;
        this.securityEventService = securityEventService;
    }

    /** Finds-or-creates the Device row for (userId, deviceId) and refreshes its metadata. Returns null if info is null. */
    @Transactional
    public Device registerDevice(Long userId, DeviceInfoRequest info) {
        if (info == null || info.getDeviceId() == null || info.getDeviceId().isBlank()) {
            return null;
        }

        LocalDateTime now = LocalDateTime.now();
        Device device = deviceRepository.findByUserIdAndDeviceId(userId, info.getDeviceId()).orElse(null);
        boolean isNewDevice = device == null;
        if (device == null) {
            device = new Device();
            device.setUserId(userId);
            device.setDeviceId(info.getDeviceId());
            device.setCreatedAt(now);
        }

        device.setPlatform(normalizePlatform(info.getPlatform()));
        device.setOsName(truncate(info.getOsName(), 50));
        device.setOsVersion(truncate(info.getOsVersion(), 30));
        device.setAppVersion(truncate(info.getAppVersion(), 30));
        device.setBrowserName(truncate(info.getBrowserName(), 50));
        // Web's WebBrowserInfo.appVersion is the browser's full appVersion
        // string (effectively the whole User-Agent in Chrome), not a short
        // version number — this genuinely overflowed a narrower column
        // during Phase 1 testing, hence the defensive truncation here on
        // top of the column itself being widened.
        device.setBrowserVersion(truncate(info.getBrowserVersion(), 255));
        device.setDeviceModel(truncate(info.getDeviceModel(), 100));
        if (info.getPushToken() != null && !info.getPushToken().isBlank()) {
            device.setPushToken(info.getPushToken());
        }
        device.setUpdatedAt(now);

        Device saved = deviceRepository.save(device);

        if (isNewDevice) {
            securityEventService.record(userId, SecurityEvent.EventType.NEW_DEVICE, saved.getId(), null,
                    null, null, Map.of("platform", saved.getPlatform() == null ? "" : saved.getPlatform()));
        }
        return saved;
    }

    /**
     * Marks any existing ACTIVE session for this device REPLACED (a device
     * has at most one live session at a time — re-logging in on the same
     * phone naturally supersedes its own prior session) and creates a fresh
     * ACTIVE one. Returns null if deviceId is null (device info was absent).
     */
    @Transactional
    public UserSession createSession(Long userId, Long deviceId, String ipAddress) {
        if (deviceId == null) {
            return null;
        }

        userSessionRepository.findByDeviceIdAndStatus(deviceId, UserSession.Status.ACTIVE.name())
                .ifPresent(existing -> {
                    existing.setStatus(UserSession.Status.REPLACED.name());
                    existing.setRevokedAt(LocalDateTime.now());
                    existing.setRevokedReason("replaced_by_new_login");
                    userSessionRepository.save(existing);
                });

        UserSession session = new UserSession();
        session.setUserId(userId);
        session.setDeviceId(deviceId);
        session.setSessionToken(UUID.randomUUID().toString());
        session.setStatus(UserSession.Status.ACTIVE.name());
        session.setIpAddress(ipAddress);
        session.setCreatedAt(LocalDateTime.now());
        session.setLastActiveAt(LocalDateTime.now());

        UserSession saved = userSessionRepository.save(session);
        securityEventService.record(userId, SecurityEvent.EventType.LOGIN, deviceId, saved.getId(), ipAddress, null, null);
        return saved;
    }

    /**
     * Called on every authenticated request by JwtAuthenticationFilter.
     * Throttles the last-active write so routine traffic doesn't turn into
     * a DB write per request.
     */
    @Transactional
    public SessionCheckResult checkAndTouch(String sessionToken) {
        if (sessionToken == null || sessionToken.isBlank()) {
            return SessionCheckResult.NOT_TRACKED;
        }

        Optional<UserSession> opt = userSessionRepository.findBySessionToken(sessionToken);
        if (opt.isEmpty()) {
            return SessionCheckResult.REVOKED;
        }

        UserSession session = opt.get();
        if (!UserSession.Status.ACTIVE.name().equals(session.getStatus())) {
            return SessionCheckResult.REVOKED;
        }

        LocalDateTime now = LocalDateTime.now();
        if (session.getLastActiveAt() == null
                || session.getLastActiveAt().isBefore(now.minusSeconds(LAST_ACTIVE_THROTTLE_SECONDS))) {
            session.setLastActiveAt(now);
            userSessionRepository.save(session);
        }
        return SessionCheckResult.ACTIVE;
    }

    /** Revokes the caller's own current session at logout. */
    @Transactional
    public void revokeSessionByToken(Long userId, String sessionToken, String reason) {
        if (sessionToken == null) {
            return;
        }
        userSessionRepository.findBySessionToken(sessionToken).ifPresent(session -> {
            if (!session.getUserId().equals(userId)) {
                return; // not this user's session — silently ignore rather than leak existence
            }
            session.setStatus(UserSession.Status.REVOKED.name());
            session.setRevokedAt(LocalDateTime.now());
            session.setRevokedReason(reason);
            userSessionRepository.save(session);
            securityEventService.record(userId, SecurityEvent.EventType.LOGOUT, session.getDeviceId(), session.getId(), null, null, null);
        });
    }

    /** Remote "log out this device" — must belong to the caller. */
    @Transactional
    public void revokeDeviceSession(Long callerUserId, Long deviceId, String reason) {
        Device device = deviceRepository.findById(deviceId)
                .orElseThrow(() -> new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND,
                        "Device not found", HttpStatus.NOT_FOUND));
        if (!device.getUserId().equals(callerUserId)) {
            throw new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND,
                    "Device not found", HttpStatus.NOT_FOUND);
        }

        Optional<UserSession> activeSession = userSessionRepository.findByDeviceIdAndStatus(deviceId, UserSession.Status.ACTIVE.name());
        activeSession.ifPresent(session -> {
            session.setStatus(UserSession.Status.REVOKED.name());
            session.setRevokedAt(LocalDateTime.now());
            session.setRevokedReason(reason);
            userSessionRepository.save(session);
        });

        securityEventService.record(callerUserId, SecurityEvent.EventType.SESSION_REVOKED, deviceId,
                activeSession.map(UserSession::getId).orElse(null), null, null, Map.of("reason", reason));
    }

    /** GET /devices — every device this user has ever registered, with its current session status folded in. */
    @Transactional(readOnly = true)
    public List<DeviceResponse> listDevices(Long userId, String currentSessionToken) {
        List<Device> devices = deviceRepository.findByUserId(userId);
        List<UserSession> sessions = userSessionRepository.findByUserId(userId);

        List<DeviceResponse> result = new ArrayList<>();
        for (Device device : devices) {
            UserSession latest = sessions.stream()
                    .filter(s -> s.getDeviceId().equals(device.getId()))
                    .max((a, b) -> a.getCreatedAt().compareTo(b.getCreatedAt()))
                    .orElse(null);

            DeviceResponse dto = new DeviceResponse();
            dto.setDeviceId(device.getId());
            dto.setPlatform(device.getPlatform());
            dto.setOsName(device.getOsName());
            dto.setOsVersion(device.getOsVersion());
            dto.setAppVersion(device.getAppVersion());
            dto.setBrowserName(device.getBrowserName());
            dto.setBrowserVersion(device.getBrowserVersion());
            dto.setDeviceModel(device.getDeviceModel());
            if (latest != null) {
                dto.setSessionStatus(latest.getStatus());
                dto.setLoginTime(latest.getCreatedAt());
                dto.setLastActiveAt(latest.getLastActiveAt());
                dto.setCurrentDevice(latest.getSessionToken().equals(currentSessionToken));
            }
            result.add(dto);
        }
        return result;
    }

    private String truncate(String value, int maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    private String normalizePlatform(String raw) {
        if (raw == null) return null;
        try {
            return Device.Platform.valueOf(raw.trim().toUpperCase()).name();
        } catch (IllegalArgumentException e) {
            return null;
        }
    }
}
