package com.socialmedia.auth.service;

import com.socialmedia.auth.dto.DeviceInfoRequest;
import com.socialmedia.auth.dto.DeviceResponse;
import com.socialmedia.auth.entity.Device;
import com.socialmedia.auth.entity.SecurityEvent;
import com.socialmedia.auth.entity.UserSession;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.repository.DeviceRepository;
import com.socialmedia.auth.repository.UserSessionRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Phase 10 hardening pass: DeviceSessionService had zero test coverage
 * despite owning the devices/user_sessions tables central to Phase 1's
 * revocation model — the actual live-curl verification in Phase 1 covered
 * end-to-end behavior, but nothing here protects against a regression at
 * the unit level. save() calls are stubbed to return their argument
 * unchanged (matching this class's own pattern of relying on the saved
 * entity's mutated-in-place state, not a distinct returned object).
 */
@ExtendWith(MockitoExtension.class)
class DeviceSessionServiceTest {

    @Mock private DeviceRepository deviceRepository;
    @Mock private UserSessionRepository userSessionRepository;
    @Mock private SecurityEventService securityEventService;

    private DeviceSessionService service;

    @BeforeEach
    void setUp() {
        service = new DeviceSessionService(deviceRepository, userSessionRepository, securityEventService);
    }

    // ---- registerDevice ----

    @Test
    void registerDevice_returnsNull_whenInfoIsNull() {
        assertNull(service.registerDevice(1L, null));
        verify(deviceRepository, never()).save(any());
    }

    @Test
    void registerDevice_returnsNull_whenDeviceIdBlank() {
        DeviceInfoRequest info = new DeviceInfoRequest();
        info.setDeviceId("   ");
        assertNull(service.registerDevice(1L, info));
        verify(deviceRepository, never()).save(any());
    }

    @Test
    void registerDevice_createsNewDevice_andFiresNewDeviceEvent() {
        DeviceInfoRequest info = new DeviceInfoRequest();
        info.setDeviceId("device-abc");
        info.setPlatform("android");
        when(deviceRepository.findByUserIdAndDeviceId(1L, "device-abc")).thenReturn(Optional.empty());
        when(deviceRepository.save(any(Device.class))).thenAnswer(inv -> {
            Device d = inv.getArgument(0);
            d.setId(99L);
            return d;
        });

        Device result = service.registerDevice(1L, info);

        assertEquals(99L, result.getId());
        assertEquals("ANDROID", result.getPlatform()); // normalized to the enum's uppercase name
        verify(securityEventService).record(eq(1L), eq(SecurityEvent.EventType.NEW_DEVICE), eq(99L),
                any(), any(), any(), any());
    }

    @Test
    void registerDevice_existingDevice_updatesInPlace_doesNotFireNewDeviceEvent() {
        Device existing = new Device();
        existing.setId(7L);
        existing.setUserId(1L);
        existing.setDeviceId("device-abc");
        DeviceInfoRequest info = new DeviceInfoRequest();
        info.setDeviceId("device-abc");
        info.setOsName("Android 14");
        when(deviceRepository.findByUserIdAndDeviceId(1L, "device-abc")).thenReturn(Optional.of(existing));
        when(deviceRepository.save(any(Device.class))).thenAnswer(inv -> inv.getArgument(0));

        Device result = service.registerDevice(1L, info);

        assertEquals(7L, result.getId());
        assertEquals("Android 14", result.getOsName());
        verify(securityEventService, never()).record(anyLong(), eq(SecurityEvent.EventType.NEW_DEVICE),
                any(), any(), any(), any(), any());
    }

    @Test
    void registerDevice_invalidPlatform_normalizesToNullInsteadOfThrowing() {
        Device existing = new Device();
        existing.setId(7L);
        DeviceInfoRequest info = new DeviceInfoRequest();
        info.setDeviceId("device-abc");
        info.setPlatform("not-a-real-platform");
        when(deviceRepository.findByUserIdAndDeviceId(1L, "device-abc")).thenReturn(Optional.of(existing));
        when(deviceRepository.save(any(Device.class))).thenAnswer(inv -> inv.getArgument(0));

        Device result = service.registerDevice(1L, info);

        assertNull(result.getPlatform());
    }

    @Test
    void registerDevice_truncatesOverlongFields_ratherThanOverflowingColumns() {
        // Real Phase 1 bug: device_info_plus's WebBrowserInfo.appVersion on
        // web returns the ENTIRE User-Agent string, which overflowed a
        // narrower column before the defensive truncation below existed.
        Device existing = new Device();
        existing.setId(7L);
        DeviceInfoRequest info = new DeviceInfoRequest();
        info.setDeviceId("device-abc");
        info.setOsName("x".repeat(80));       // column limit 50
        info.setBrowserVersion("y".repeat(300)); // column limit 255
        when(deviceRepository.findByUserIdAndDeviceId(1L, "device-abc")).thenReturn(Optional.of(existing));
        when(deviceRepository.save(any(Device.class))).thenAnswer(inv -> inv.getArgument(0));

        Device result = service.registerDevice(1L, info);

        assertEquals(50, result.getOsName().length());
        assertEquals(255, result.getBrowserVersion().length());
    }

    // ---- createSession ----

    @Test
    void createSession_returnsNull_whenDeviceIdIsNull() {
        assertNull(service.createSession(1L, null, "127.0.0.1"));
        verify(userSessionRepository, never()).save(any());
    }

    @Test
    void createSession_replacesExistingActiveSession_onSameDevice() {
        UserSession existingActive = new UserSession();
        existingActive.setId(5L);
        existingActive.setStatus(UserSession.Status.ACTIVE.name());
        when(userSessionRepository.findByDeviceIdAndStatus(42L, UserSession.Status.ACTIVE.name()))
                .thenReturn(Optional.of(existingActive));
        when(userSessionRepository.save(any(UserSession.class))).thenAnswer(inv -> inv.getArgument(0));

        UserSession created = service.createSession(1L, 42L, "127.0.0.1");

        assertEquals(UserSession.Status.REPLACED.name(), existingActive.getStatus());
        assertEquals("replaced_by_new_login", existingActive.getRevokedReason());
        assertEquals(UserSession.Status.ACTIVE.name(), created.getStatus());
        assertEquals(42L, created.getDeviceId());
        verify(userSessionRepository, times(2)).save(any(UserSession.class)); // the replaced one + the new one
        verify(securityEventService).record(eq(1L), eq(SecurityEvent.EventType.LOGIN), eq(42L),
                any(), eq("127.0.0.1"), any(), any());
    }

    @Test
    void createSession_noExistingSession_justCreatesOne() {
        when(userSessionRepository.findByDeviceIdAndStatus(42L, UserSession.Status.ACTIVE.name()))
                .thenReturn(Optional.empty());
        when(userSessionRepository.save(any(UserSession.class))).thenAnswer(inv -> inv.getArgument(0));

        UserSession created = service.createSession(1L, 42L, "127.0.0.1");

        assertEquals(UserSession.Status.ACTIVE.name(), created.getStatus());
        verify(userSessionRepository, times(1)).save(any(UserSession.class));
    }

    // ---- checkAndTouch ----

    @Test
    void checkAndTouch_blankToken_returnsNotTracked_legacyTokenBehavior() {
        assertEquals(DeviceSessionService.SessionCheckResult.NOT_TRACKED, service.checkAndTouch(null));
        assertEquals(DeviceSessionService.SessionCheckResult.NOT_TRACKED, service.checkAndTouch(""));
        verify(userSessionRepository, never()).findBySessionToken(any());
    }

    @Test
    void checkAndTouch_unknownToken_returnsRevoked() {
        when(userSessionRepository.findBySessionToken("ghost")).thenReturn(Optional.empty());
        assertEquals(DeviceSessionService.SessionCheckResult.REVOKED, service.checkAndTouch("ghost"));
    }

    @Test
    void checkAndTouch_nonActiveStatus_returnsRevoked() {
        UserSession session = new UserSession();
        session.setStatus(UserSession.Status.REVOKED.name());
        when(userSessionRepository.findBySessionToken("tok")).thenReturn(Optional.of(session));
        assertEquals(DeviceSessionService.SessionCheckResult.REVOKED, service.checkAndTouch("tok"));
        verify(userSessionRepository, never()).save(any());
    }

    @Test
    void checkAndTouch_activeAndStale_touchesAndSaves() {
        UserSession session = new UserSession();
        session.setStatus(UserSession.Status.ACTIVE.name());
        session.setLastActiveAt(LocalDateTime.now().minusMinutes(5)); // older than the 60s throttle
        when(userSessionRepository.findBySessionToken("tok")).thenReturn(Optional.of(session));

        DeviceSessionService.SessionCheckResult result = service.checkAndTouch("tok");

        assertEquals(DeviceSessionService.SessionCheckResult.ACTIVE, result);
        verify(userSessionRepository).save(session);
    }

    @Test
    void checkAndTouch_activeAndRecent_skipsWrite_throttled() {
        // The whole point of the throttle: routine traffic within the same
        // 60s window must NOT turn into a DB write per request.
        UserSession session = new UserSession();
        session.setStatus(UserSession.Status.ACTIVE.name());
        session.setLastActiveAt(LocalDateTime.now().minusSeconds(5));
        when(userSessionRepository.findBySessionToken("tok")).thenReturn(Optional.of(session));

        DeviceSessionService.SessionCheckResult result = service.checkAndTouch("tok");

        assertEquals(DeviceSessionService.SessionCheckResult.ACTIVE, result);
        verify(userSessionRepository, never()).save(any());
    }

    // ---- revokeSessionByToken ----

    @Test
    void revokeSessionByToken_nullToken_isNoOp() {
        service.revokeSessionByToken(1L, null, "logout");
        verify(userSessionRepository, never()).findBySessionToken(any());
    }

    @Test
    void revokeSessionByToken_belongsToDifferentUser_silentlyIgnored() {
        UserSession session = new UserSession();
        session.setUserId(999L); // not the caller
        session.setStatus(UserSession.Status.ACTIVE.name());
        when(userSessionRepository.findBySessionToken("tok")).thenReturn(Optional.of(session));

        service.revokeSessionByToken(1L, "tok", "logout");

        verify(userSessionRepository, never()).save(any());
        verify(securityEventService, never()).record(anyLong(), any(), any(), any(), any(), any(), any());
    }

    @Test
    void revokeSessionByToken_ownSession_revokesAndFiresLogoutEvent() {
        UserSession session = new UserSession();
        session.setId(3L);
        session.setUserId(1L);
        session.setDeviceId(42L);
        session.setStatus(UserSession.Status.ACTIVE.name());
        when(userSessionRepository.findBySessionToken("tok")).thenReturn(Optional.of(session));

        service.revokeSessionByToken(1L, "tok", "user_logout");

        assertEquals(UserSession.Status.REVOKED.name(), session.getStatus());
        assertEquals("user_logout", session.getRevokedReason());
        verify(userSessionRepository).save(session);
        verify(securityEventService).record(1L, SecurityEvent.EventType.LOGOUT, 42L, 3L, null, null, null);
    }

    // ---- revokeDeviceSession ----

    @Test
    void revokeDeviceSession_deviceNotFound_throws() {
        when(deviceRepository.findById(1L)).thenReturn(Optional.empty());
        assertThrows(AuthApiException.class, () -> service.revokeDeviceSession(1L, 1L, "user_requested"));
    }

    @Test
    void revokeDeviceSession_belongsToAnotherUser_throwsNotFound_noExistenceLeak() {
        // Deliberately the SAME error as "device not found" — see the
        // service's own comment about not leaking cross-user existence.
        Device device = new Device();
        device.setId(1L);
        device.setUserId(999L); // not the caller
        when(deviceRepository.findById(1L)).thenReturn(Optional.of(device));

        AuthApiException ex = assertThrows(AuthApiException.class,
                () -> service.revokeDeviceSession(1L, 1L, "user_requested"));
        assertEquals(AuthApiException.ErrorCode.USER_NOT_FOUND, ex.getErrorCode());
    }

    @Test
    void revokeDeviceSession_ownDevice_revokesActiveSession_firesEvent() {
        Device device = new Device();
        device.setId(1L);
        device.setUserId(1L);
        UserSession activeSession = new UserSession();
        activeSession.setId(8L);
        activeSession.setStatus(UserSession.Status.ACTIVE.name());
        when(deviceRepository.findById(1L)).thenReturn(Optional.of(device));
        when(userSessionRepository.findByDeviceIdAndStatus(1L, UserSession.Status.ACTIVE.name()))
                .thenReturn(Optional.of(activeSession));

        service.revokeDeviceSession(1L, 1L, "user_requested");

        assertEquals(UserSession.Status.REVOKED.name(), activeSession.getStatus());
        verify(userSessionRepository).save(activeSession);
        verify(securityEventService).record(eq(1L), eq(SecurityEvent.EventType.SESSION_REVOKED), eq(1L),
                eq(8L), any(), any(), any());
    }

    @Test
    void revokeDeviceSession_ownDevice_noActiveSession_stillFiresEvent_noSave() {
        // A device with no currently-active session (e.g. already logged
        // out elsewhere) is still a valid, harmless revoke call — must not
        // throw or silently no-op the audit trail.
        Device device = new Device();
        device.setId(1L);
        device.setUserId(1L);
        when(deviceRepository.findById(1L)).thenReturn(Optional.of(device));
        when(userSessionRepository.findByDeviceIdAndStatus(1L, UserSession.Status.ACTIVE.name()))
                .thenReturn(Optional.empty());

        service.revokeDeviceSession(1L, 1L, "user_requested");

        verify(userSessionRepository, never()).save(any());
        verify(securityEventService).record(eq(1L), eq(SecurityEvent.EventType.SESSION_REVOKED), eq(1L),
                eq(null), any(), any(), any());
    }

    // ---- listDevices ----

    @Test
    void listDevices_marksCurrentDevice_bySessionTokenMatch() {
        Device device1 = new Device();
        device1.setId(1L);
        device1.setPlatform("ANDROID");
        Device device2 = new Device();
        device2.setId(2L);
        device2.setPlatform("WEB");

        UserSession session1 = new UserSession();
        session1.setDeviceId(1L);
        session1.setSessionToken("tok-1");
        session1.setStatus("ACTIVE");
        session1.setCreatedAt(LocalDateTime.now().minusHours(1));
        UserSession session2 = new UserSession();
        session2.setDeviceId(2L);
        session2.setSessionToken("tok-2");
        session2.setStatus("ACTIVE");
        session2.setCreatedAt(LocalDateTime.now());

        when(deviceRepository.findByUserId(1L)).thenReturn(List.of(device1, device2));
        when(userSessionRepository.findByUserId(1L)).thenReturn(List.of(session1, session2));

        List<DeviceResponse> result = service.listDevices(1L, "tok-2");

        assertEquals(2, result.size());
        DeviceResponse dto1 = result.stream().filter(d -> d.getDeviceId().equals(1L)).findFirst().orElseThrow();
        DeviceResponse dto2 = result.stream().filter(d -> d.getDeviceId().equals(2L)).findFirst().orElseThrow();
        assertFalse(dto1.isCurrentDevice());
        assertTrue(dto2.isCurrentDevice());
    }

    @Test
    void listDevices_deviceWithNoSession_leavesStatusNull_notCurrentDevice() {
        Device device = new Device();
        device.setId(1L);
        when(deviceRepository.findByUserId(1L)).thenReturn(List.of(device));
        when(userSessionRepository.findByUserId(1L)).thenReturn(List.of());

        List<DeviceResponse> result = service.listDevices(1L, "some-token");

        assertEquals(1, result.size());
        assertNull(result.get(0).getSessionStatus());
        assertFalse(result.get(0).isCurrentDevice());
    }

    @Test
    void listDevices_picksLatestSession_whenMultipleExistForSameDevice() {
        Device device = new Device();
        device.setId(1L);

        UserSession older = new UserSession();
        older.setDeviceId(1L);
        older.setStatus("REPLACED");
        older.setSessionToken("old-tok");
        older.setCreatedAt(LocalDateTime.now().minusDays(1));

        UserSession newer = new UserSession();
        newer.setDeviceId(1L);
        newer.setStatus("ACTIVE");
        newer.setSessionToken("new-tok");
        newer.setCreatedAt(LocalDateTime.now());

        when(deviceRepository.findByUserId(1L)).thenReturn(List.of(device));
        when(userSessionRepository.findByUserId(1L)).thenReturn(List.of(older, newer));

        List<DeviceResponse> result = service.listDevices(1L, "new-tok");

        assertEquals("ACTIVE", result.get(0).getSessionStatus());
        assertTrue(result.get(0).isCurrentDevice());
    }
}
