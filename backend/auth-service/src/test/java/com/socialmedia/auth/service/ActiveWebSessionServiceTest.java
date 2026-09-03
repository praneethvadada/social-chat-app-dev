package com.socialmedia.auth.service;

import com.socialmedia.auth.client.ChatsServiceRelayClient;
import com.socialmedia.auth.entity.ActiveWebSession;
import com.socialmedia.auth.entity.Device;
import com.socialmedia.auth.entity.SecurityEvent;
import com.socialmedia.auth.entity.UserSession;
import com.socialmedia.auth.repository.ActiveWebSessionRepository;
import com.socialmedia.auth.repository.DeviceRepository;
import com.socialmedia.auth.repository.UserSessionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Phase 10 hardening pass: ActiveWebSessionService had zero test coverage
 * despite being Phase 5's central "single active web session" enforcement
 * point (Phase 5's own verification was live-curl-only). The
 * same-device-re-login-is-not-a-takeover guard is the single most
 * consequential piece of logic here — a wrong answer means either a
 * legitimate fresh login on the SAME browser gets incorrectly force-logged-
 * out, or a genuine cross-device takeover silently fails to revoke the old
 * session. Both directions are covered explicitly below.
 */
@ExtendWith(MockitoExtension.class)
class ActiveWebSessionServiceTest {

    @Mock private ActiveWebSessionRepository activeWebSessionRepository;
    @Mock private UserSessionRepository userSessionRepository;
    @Mock private DeviceRepository deviceRepository;
    @Mock private SecurityEventService securityEventService;
    @Mock private ChatsServiceRelayClient relayClient;

    private ActiveWebSessionService service;

    @BeforeEach
    void setUp() {
        service = new ActiveWebSessionService(activeWebSessionRepository, userSessionRepository,
                deviceRepository, securityEventService, relayClient);
    }

    private UserSession newSession(Long id) {
        UserSession s = new UserSession();
        s.setId(id);
        return s;
    }

    @Test
    void claimOrReplace_noExistingRow_firstEverWebLogin_justClaims_noRevocationNoise() {
        when(activeWebSessionRepository.lockByUserId(1L)).thenReturn(Optional.empty());

        service.claimOrReplace(1L, 100L, newSession(500L));

        ArgumentCaptor<ActiveWebSession> captor = ArgumentCaptor.forClass(ActiveWebSession.class);
        verify(activeWebSessionRepository).save(captor.capture());
        assertEquals(1L, captor.getValue().getUserId());
        assertEquals(500L, captor.getValue().getSessionId());
        assertEquals(100L, captor.getValue().getDeviceId());

        verify(userSessionRepository, never()).findById(any());
        verify(securityEventService, never()).record(anyLong(), any(), any(), any(), any(), any(), any());
        verify(relayClient, never()).relayToUser(anyLong(), any(), any());
    }

    @Test
    void claimOrReplace_sameDeviceReLogin_isNotATakeover_noRevocationNoBroadcast() {
        // The critical guard: DeviceSessionService.createSession already
        // marked this device's own prior session REPLACED before this runs
        // — firing a "you were logged out" notice here would be wrong.
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 100L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.lockByUserId(1L)).thenReturn(Optional.of(existingRow));

        service.claimOrReplace(1L, 100L, newSession(501L)); // SAME deviceId (100L) as before

        verify(activeWebSessionRepository).save(existingRow);
        assertEquals(501L, existingRow.getSessionId());
        assertEquals(100L, existingRow.getDeviceId());

        verify(userSessionRepository, never()).findById(any());
        verify(securityEventService, never()).record(anyLong(), any(), any(), any(), any(), any(), any());
        verify(relayClient, never()).relayToUser(anyLong(), any(), any());
    }

    @Test
    void claimOrReplace_differentDevice_isAGenuineTakeover_revokesOldSession_firesEvent_broadcasts() {
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 200L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.lockByUserId(1L)).thenReturn(Optional.of(existingRow));

        UserSession oldSession = newSession(499L);
        oldSession.setStatus(UserSession.Status.ACTIVE.name());
        when(userSessionRepository.findById(499L)).thenReturn(Optional.of(oldSession));

        service.claimOrReplace(1L, 100L, newSession(501L)); // DIFFERENT deviceId (100L vs old 200L)

        // Row re-pointed to the new session/device
        assertEquals(501L, existingRow.getSessionId());
        assertEquals(100L, existingRow.getDeviceId());
        verify(activeWebSessionRepository).save(existingRow);

        // Old session revoked with the right reason
        assertEquals(UserSession.Status.REVOKED.name(), oldSession.getStatus());
        assertEquals("replaced_by_new_web_login", oldSession.getRevokedReason());
        verify(userSessionRepository).save(oldSession);

        // Audit event fired with the previous device id recorded
        verify(securityEventService).record(eq(1L), eq(SecurityEvent.EventType.WEB_SESSION_REPLACED), eq(100L),
                eq(501L), any(), any(), eq(Map.of("previousDeviceId", "200")));

        // Best-effort live notice pushed to the old browser
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(relayClient).relayToUser(eq(1L), eq("/queue/security"), payloadCaptor.capture());
        assertEquals("session.revoked", payloadCaptor.getValue().get("type"));
        assertEquals(499L, payloadCaptor.getValue().get("revokedSessionId"));
        assertEquals(100L, payloadCaptor.getValue().get("newDeviceId"));
    }

    @Test
    void claimOrReplace_oldSessionAlreadyInactive_isNotAGenuineTakeover_noEventNoBroadcast() {
        // Real bug found via live user testing right after this shipped: the
        // active_web_session row isn't cleared on logout, only ever
        // overwritten by the NEXT web login — so a device that had already
        // logged out (its UserSession genuinely REVOKED) was still treated
        // as "the" active device on every subsequent different-device login,
        // firing a misleading WEB_SESSION_REPLACED event and push notice for
        // a takeover that wasn't real. The row still gets re-pointed to the
        // new session (that part is correct and harmless either way) — only
        // the event/broadcast/revoke-attempt are now correctly skipped.
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 200L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.lockByUserId(1L)).thenReturn(Optional.of(existingRow));

        UserSession oldSession = newSession(499L);
        oldSession.setStatus(UserSession.Status.REVOKED.name()); // already logged out elsewhere
        oldSession.setRevokedReason("some_other_reason");
        when(userSessionRepository.findById(499L)).thenReturn(Optional.of(oldSession));

        service.claimOrReplace(1L, 100L, newSession(501L));

        // Untouched — not re-revoked a second time
        assertEquals("some_other_reason", oldSession.getRevokedReason());
        verify(userSessionRepository, never()).save(oldSession);
        // The row still gets claimed for the new device...
        verify(activeWebSessionRepository).save(existingRow);
        assertEquals(501L, existingRow.getSessionId());
        assertEquals(100L, existingRow.getDeviceId());
        // ...but no misleading "you were logged out" event/broadcast fires
        // for a device that was already logged out.
        verify(securityEventService, never()).record(anyLong(), any(), any(), any(), any(), any(), any());
        verify(relayClient, never()).relayToUser(anyLong(), any(), any());
    }

    @Test
    void claimOrReplace_oldSessionRowNoLongerExists_isNotAGenuineTakeover_noCrash_noEvent() {
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 200L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.lockByUserId(1L)).thenReturn(Optional.of(existingRow));
        when(userSessionRepository.findById(499L)).thenReturn(Optional.empty());

        service.claimOrReplace(1L, 100L, newSession(501L));

        verify(activeWebSessionRepository).save(existingRow);
        verify(securityEventService, never()).record(anyLong(), any(), any(), any(), any(), any(), any());
        verify(relayClient, never()).relayToUser(anyLong(), any(), any());
    }

    // ---- findConflictingDevice (post-Phase-10: confirm-before-kick pre-check) ----

    private Device device(Long id, String clientDeviceId) {
        Device d = new Device();
        d.setId(id);
        d.setDeviceId(clientDeviceId);
        return d;
    }

    @Test
    void findConflictingDevice_noExistingSession_empty() {
        when(activeWebSessionRepository.findByUserId(1L)).thenReturn(Optional.empty());

        assertTrue(service.findConflictingDevice(1L, "client-uuid-A").isEmpty());
        verify(deviceRepository, never()).findById(any());
    }

    private UserSession activeSession(Long id) {
        UserSession s = newSession(id);
        s.setStatus(UserSession.Status.ACTIVE.name());
        return s;
    }

    @Test
    void findConflictingDevice_sameDeviceReLogging_empty_notAConflict() {
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 200L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.findByUserId(1L)).thenReturn(Optional.of(existingRow));
        when(userSessionRepository.findById(499L)).thenReturn(Optional.of(activeSession(499L)));
        when(deviceRepository.findById(200L)).thenReturn(Optional.of(device(200L, "client-uuid-A")));

        // Incoming login is from the SAME client device (matching UUID) that already owns the session.
        assertTrue(service.findConflictingDevice(1L, "client-uuid-A").isEmpty());
    }

    @Test
    void findConflictingDevice_differentDevice_returnsTheConflictingOne() {
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 200L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.findByUserId(1L)).thenReturn(Optional.of(existingRow));
        when(userSessionRepository.findById(499L)).thenReturn(Optional.of(activeSession(499L)));
        Device existingDevice = device(200L, "client-uuid-OLD");
        when(deviceRepository.findById(200L)).thenReturn(Optional.of(existingDevice));

        Optional<Device> result = service.findConflictingDevice(1L, "client-uuid-NEW");

        assertTrue(result.isPresent());
        assertEquals(existingDevice, result.get());
    }

    @Test
    void findConflictingDevice_incomingDeviceIdNull_treatedAsConflict_failsSafe() {
        // Defensive: DeviceInfoRequest.deviceId is @NotBlank in practice, so
        // this shouldn't occur — but if it somehow did, err toward requiring
        // confirmation rather than silently allowing a takeover.
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 200L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.findByUserId(1L)).thenReturn(Optional.of(existingRow));
        when(userSessionRepository.findById(499L)).thenReturn(Optional.of(activeSession(499L)));
        when(deviceRepository.findById(200L)).thenReturn(Optional.of(device(200L, "client-uuid-OLD")));

        assertFalse(service.findConflictingDevice(1L, null).isEmpty());
    }

    @Test
    void findConflictingDevice_previousSessionAlreadyLoggedOut_empty_notAConflict() {
        // The exact bug found via live user testing: the active_web_session
        // row is never cleared on logout, only ever overwritten by the NEXT
        // web login — so a device that had already properly logged out
        // (its UserSession genuinely REVOKED) must NOT still be reported as
        // "the" active device, or every fresh login on a different browser
        // incorrectly demands confirmation against a session that no longer
        // meaningfully exists.
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 200L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.findByUserId(1L)).thenReturn(Optional.of(existingRow));
        UserSession loggedOutSession = newSession(499L);
        loggedOutSession.setStatus(UserSession.Status.REVOKED.name());
        when(userSessionRepository.findById(499L)).thenReturn(Optional.of(loggedOutSession));

        assertTrue(service.findConflictingDevice(1L, "client-uuid-NEW").isEmpty());
        verify(deviceRepository, never()).findById(any());
    }

    @Test
    void findConflictingDevice_previousSessionRowMissing_empty_notAConflict() {
        ActiveWebSession existingRow = new ActiveWebSession(1L, 499L, 200L, java.time.LocalDateTime.now());
        when(activeWebSessionRepository.findByUserId(1L)).thenReturn(Optional.of(existingRow));
        when(userSessionRepository.findById(499L)).thenReturn(Optional.empty());

        assertTrue(service.findConflictingDevice(1L, "client-uuid-NEW").isEmpty());
        verify(deviceRepository, never()).findById(any());
    }
}
