package com.socialmedia.auth.service;

import com.socialmedia.auth.client.ChatsServiceRelayClient;
import com.socialmedia.auth.entity.ActiveWebSession;
import com.socialmedia.auth.entity.Device;
import com.socialmedia.auth.entity.SecurityEvent;
import com.socialmedia.auth.entity.UserSession;
import com.socialmedia.auth.repository.ActiveWebSessionRepository;
import com.socialmedia.auth.repository.DeviceRepository;
import com.socialmedia.auth.repository.UserSessionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;

/**
 * Single-active-web-session enforcement (spec: only one browser may be
 * logged in at a time per account, like WhatsApp Web). active_web_session
 * has exactly one row per user (userId is the PK), mirroring
 * MobileStorageOwner's exact pattern - "at most one active web session" is
 * a database-level guarantee via lockByUserId's pessimistic lock, not
 * something re-verified in application code.
 */
@Service
public class ActiveWebSessionService {

    private final ActiveWebSessionRepository activeWebSessionRepository;
    private final UserSessionRepository userSessionRepository;
    private final DeviceRepository deviceRepository;
    private final SecurityEventService securityEventService;
    private final ChatsServiceRelayClient relayClient;

    public ActiveWebSessionService(ActiveWebSessionRepository activeWebSessionRepository,
                                    UserSessionRepository userSessionRepository,
                                    DeviceRepository deviceRepository,
                                    SecurityEventService securityEventService,
                                    ChatsServiceRelayClient relayClient) {
        this.activeWebSessionRepository = activeWebSessionRepository;
        this.userSessionRepository = userSessionRepository;
        this.deviceRepository = deviceRepository;
        this.securityEventService = securityEventService;
        this.relayClient = relayClient;
    }

    /**
     * Post-Phase-10 UX change: read-only pre-check (no locking, no
     * mutation) used BEFORE finishLogin() creates any device/session row,
     * to decide whether this WEB login needs the user's explicit
     * confirmation before claimOrReplace() below is allowed to run at all.
     * Previously claimOrReplace() ran unconditionally on every WEB login,
     * silently kicking whichever device held the session — now the caller
     * only proceeds to claimOrReplace() after the user has confirmed via
     * POST /login/web-session/confirm (see AuthService.finishLogin).
     *
     * Returns the device CURRENTLY holding the active session if it's
     * genuinely a different device than the one logging in now (same-device
     * re-login is never a conflict — identical reasoning to
     * claimOrReplace's own isGenuineTakeover check); empty if there's no
     * active session yet, or it's already this exact device.
     *
     * Real bug found via live testing right after this shipped: logging out
     * of a browser does NOT clear this row — it only ever gets overwritten
     * by the NEXT successful web login (see claimOrReplace below, which
     * only reads/writes it, never deletes it on logout). So a device that
     * had already properly logged out was still being reported as "the"
     * active device, making every fresh login on a SECOND browser trigger a
     * confirmation prompt against a session that no longer meaningfully
     * existed. Fixed by also checking that the underlying UserSession this
     * row points at is still genuinely ACTIVE (not REVOKED/REPLACED/
     * EXPIRED) before treating it as a real conflict worth asking about.
     */
    @Transactional(readOnly = true)
    public Optional<Device> findConflictingDevice(Long userId, String incomingClientDeviceId) {
        Optional<ActiveWebSession> existing = activeWebSessionRepository.findByUserId(userId);
        if (existing.isEmpty()) {
            return Optional.empty();
        }
        ActiveWebSession row = existing.get();

        boolean stillActive = userSessionRepository.findById(row.getSessionId())
                .map(s -> UserSession.Status.ACTIVE.name().equals(s.getStatus()))
                .orElse(false);
        if (!stillActive) {
            return Optional.empty();
        }

        return deviceRepository.findById(row.getDeviceId())
                .filter(existingDevice -> incomingClientDeviceId == null
                        || !incomingClientDeviceId.equals(existingDevice.getDeviceId()));
    }

    /**
     * Called right after a WEB-platform login/register creates its
     * UserSession (see AuthService). If a DIFFERENT device previously held
     * the account's active web session, that old session is revoked
     * immediately - its very next REST call or WebSocket frame against
     * chats-service is rejected (see SessionStatusClient there) - and,
     * best-effort, a live notice is pushed so the old browser can react
     * without waiting for a request to fail first.
     *
     * Same-device re-login (a refreshed tab, or logging in again on the
     * same browser) is NOT a takeover: DeviceSessionService.createSession
     * already marks that device's own prior session REPLACED before this
     * runs, so previousDeviceId will equal the new deviceId and nothing
     * fires - a browser must never receive a "you were logged out"
     * notice for its own fresh login.
     *
     * Also not a genuine takeover: the previous session already isn't
     * ACTIVE (its owner already logged out, or was already kicked some
     * other way) — same reasoning as findConflictingDevice's own fix above.
     * Without this, a device that had already properly logged out would
     * still generate a WEB_SESSION_REPLACED audit event and a "you were
     * logged out" push notice every time — misleading, and pure noise.
     */
    @Transactional
    public void claimOrReplace(Long userId, Long deviceId, UserSession newSession) {
        Optional<ActiveWebSession> existing = activeWebSessionRepository.lockByUserId(userId);

        Long previousSessionId = existing.map(ActiveWebSession::getSessionId).orElse(null);
        Long previousDeviceId = existing.map(ActiveWebSession::getDeviceId).orElse(null);
        // Device-id comparison first (cheap, no DB call) so the common
        // same-device-relogin fast path never touches userSessionRepository
        // at all — only a genuinely-different device needs the extra
        // "is it still active" lookup below.
        boolean differentDevice = previousSessionId != null
                && previousDeviceId != null
                && !previousDeviceId.equals(deviceId);
        boolean isGenuineTakeover = differentDevice
                && userSessionRepository.findById(previousSessionId)
                        .map(s -> UserSession.Status.ACTIVE.name().equals(s.getStatus()))
                        .orElse(false);

        if (existing.isPresent()) {
            ActiveWebSession row = existing.get();
            row.setSessionId(newSession.getId());
            row.setDeviceId(deviceId);
            row.setGrantedAt(LocalDateTime.now());
            activeWebSessionRepository.save(row);
        } else {
            activeWebSessionRepository.save(new ActiveWebSession(userId, newSession.getId(), deviceId, LocalDateTime.now()));
        }

        if (!isGenuineTakeover) {
            return;
        }

        userSessionRepository.findById(previousSessionId).ifPresent(old -> {
            if (UserSession.Status.ACTIVE.name().equals(old.getStatus())) {
                old.setStatus(UserSession.Status.REVOKED.name());
                old.setRevokedAt(LocalDateTime.now());
                old.setRevokedReason("replaced_by_new_web_login");
                userSessionRepository.save(old);
            }
        });

        securityEventService.record(userId, SecurityEvent.EventType.WEB_SESSION_REPLACED, deviceId, newSession.getId(),
                null, null, Map.of("previousDeviceId", previousDeviceId.toString()));

        // Best-effort live notice to the old browser, if it's currently
        // connected - see ChatsServiceRelayClient's own doc comment. The
        // real enforcement is SessionStatusClient rejecting its next
        // request/frame regardless of whether this notice ever arrives.
        relayClient.relayToUser(userId, "/queue/security", Map.of(
                "type", "session.revoked",
                "reason", "replaced_by_new_web_login",
                "revokedSessionId", previousSessionId,
                "newDeviceId", deviceId
        ));
    }
}
