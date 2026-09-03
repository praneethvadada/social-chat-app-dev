package com.socialmedia.auth.service;

import com.socialmedia.auth.client.ChatsServiceRelayClient;
import com.socialmedia.auth.dto.MobileStorageStatusResponse;
import com.socialmedia.auth.entity.Device;
import com.socialmedia.auth.entity.MobileStorageHistory;
import com.socialmedia.auth.entity.MobileStorageOwner;
import com.socialmedia.auth.entity.SecurityEvent;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.repository.DeviceRepository;
import com.socialmedia.auth.repository.MobileStorageHistoryRepository;
import com.socialmedia.auth.repository.MobileStorageOwnerRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

import java.util.Map;
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
 * Phase 10 hardening pass: MobileStorageService had zero test coverage
 * despite being Phase 3's central single-active-mobile-storage-owner
 * enforcement (Phase 3's own verification was live-curl-only). The two
 * riskiest behaviors — a WEB/desktop device never being allowed to claim
 * local chat storage, and a same-device claim/transfer being a true no-op
 * rather than spuriously revoking/notifying the calling device about
 * itself — are covered explicitly below.
 */
@ExtendWith(MockitoExtension.class)
class MobileStorageServiceTest {

    @Mock private MobileStorageOwnerRepository ownerRepository;
    @Mock private MobileStorageHistoryRepository historyRepository;
    @Mock private DeviceRepository deviceRepository;
    @Mock private SecurityEventService securityEventService;
    @Mock private ChatsServiceRelayClient relayClient;

    private MobileStorageService service;

    @BeforeEach
    void setUp() {
        service = new MobileStorageService(ownerRepository, historyRepository, deviceRepository,
                securityEventService, relayClient);
    }

    private Device mobileDevice(Long id) {
        Device d = new Device();
        d.setId(id);
        d.setPlatform("ANDROID");
        return d;
    }

    // ---- getStatus ----

    @Test
    void getStatus_neverClaimed_returnsNotOwnerWithNullDevice() {
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.empty());

        MobileStorageStatusResponse result = service.getStatus(1L, 10L);

        assertFalse(result.isOwner());
        assertNull(result.getOwnerDevice());
    }

    @Test
    void getStatus_callingDeviceIsOwner_returnsIsOwnerTrue() {
        MobileStorageOwner owner = new MobileStorageOwner(1L, 10L, java.time.LocalDateTime.now());
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.of(owner));
        when(deviceRepository.findById(10L)).thenReturn(Optional.of(mobileDevice(10L)));

        MobileStorageStatusResponse result = service.getStatus(1L, 10L);

        assertTrue(result.isOwner());
        assertEquals(10L, result.getOwnerDevice().getDeviceId());
    }

    @Test
    void getStatus_callingDeviceIsNotOwner_returnsIsOwnerFalse_butStillReportsOwnerInfo() {
        MobileStorageOwner owner = new MobileStorageOwner(1L, 10L, java.time.LocalDateTime.now());
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.of(owner));
        when(deviceRepository.findById(10L)).thenReturn(Optional.of(mobileDevice(10L)));

        MobileStorageStatusResponse result = service.getStatus(1L, 999L); // different device asking

        assertFalse(result.isOwner());
        assertEquals(10L, result.getOwnerDevice().getDeviceId()); // still reports who owns it
    }

    // ---- claim ----

    @Test
    void claim_nonMobileDevice_rejectsBeforeTouchingOwnerRow() {
        Device webDevice = new Device();
        webDevice.setId(20L);
        webDevice.setPlatform("WEB");
        when(deviceRepository.findById(20L)).thenReturn(Optional.of(webDevice));

        AuthApiException ex = assertThrows(AuthApiException.class, () -> service.claim(1L, 20L));

        assertEquals(AuthApiException.ErrorCode.MOBILE_ONLY_FEATURE, ex.getErrorCode());
        verify(ownerRepository, never()).lockByUserId(any());
    }

    @Test
    void claim_unknownDevice_throwsDeviceUnknown() {
        when(deviceRepository.findById(20L)).thenReturn(Optional.empty());

        AuthApiException ex = assertThrows(AuthApiException.class, () -> service.claim(1L, 20L));

        assertEquals(AuthApiException.ErrorCode.DEVICE_UNKNOWN, ex.getErrorCode());
    }

    @Test
    void claim_firstEverClaim_createsOwnerRow_recordsHistoryAndEvent() {
        when(deviceRepository.findById(10L)).thenReturn(Optional.of(mobileDevice(10L)));
        when(ownerRepository.lockByUserId(1L)).thenReturn(Optional.empty());
        // getStatus() call at the end re-reads via findByUserId (not the locked variant)
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.of(new MobileStorageOwner(1L, 10L, java.time.LocalDateTime.now())));

        MobileStorageStatusResponse result = service.claim(1L, 10L);

        ArgumentCaptor<MobileStorageOwner> captor = ArgumentCaptor.forClass(MobileStorageOwner.class);
        verify(ownerRepository).save(captor.capture());
        assertEquals(1L, captor.getValue().getUserId());
        assertEquals(10L, captor.getValue().getDeviceId());

        ArgumentCaptor<MobileStorageHistory> historyCaptor = ArgumentCaptor.forClass(MobileStorageHistory.class);
        verify(historyRepository).save(historyCaptor.capture());
        assertNull(historyCaptor.getValue().getFromDeviceId());
        assertEquals(10L, historyCaptor.getValue().getToDeviceId());

        verify(securityEventService).record(eq(1L), eq(SecurityEvent.EventType.LOCAL_STORAGE_DEVICE_CHANGED),
                eq(10L), any(), any(), any(), eq(Map.of("fromDeviceId", "none")));
        assertTrue(result.isOwner());
    }

    @Test
    void claim_alreadyOwnedByAnyDevice_isANoOp_doesNotOverwriteOrRecordHistory() {
        // claim() is explicitly documented as not the right call to take
        // ownership from someone else — that's transfer()'s job.
        when(deviceRepository.findById(10L)).thenReturn(Optional.of(mobileDevice(10L)));
        when(ownerRepository.lockByUserId(1L)).thenReturn(Optional.of(new MobileStorageOwner(1L, 999L, java.time.LocalDateTime.now())));
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.of(new MobileStorageOwner(1L, 999L, java.time.LocalDateTime.now())));

        MobileStorageStatusResponse result = service.claim(1L, 10L);

        verify(ownerRepository, never()).save(any());
        verify(historyRepository, never()).save(any());
        verify(securityEventService, never()).record(anyLong(), any(), any(), any(), any(), any(), any());
        assertFalse(result.isOwner()); // 999L owns it, not the calling device 10L
    }

    @Test
    void claim_racedAgainstAnotherFirstClaim_gracefullyReportsWhoeverWon() {
        when(deviceRepository.findById(10L)).thenReturn(Optional.of(mobileDevice(10L)));
        when(ownerRepository.lockByUserId(1L)).thenReturn(Optional.empty());
        when(ownerRepository.save(any())).thenThrow(new DataIntegrityViolationException("unique constraint"));
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.of(new MobileStorageOwner(1L, 777L, java.time.LocalDateTime.now())));

        MobileStorageStatusResponse result = service.claim(1L, 10L);

        assertFalse(result.isOwner()); // lost the race to device 777L
        verify(historyRepository, never()).save(any());
    }

    // ---- transfer ----

    @Test
    void transfer_nonMobileCallingDevice_rejected() {
        Device webDevice = new Device();
        webDevice.setId(20L);
        webDevice.setPlatform("IOS_UNKNOWN_TYPO"); // not ANDROID/IOS
        when(deviceRepository.findById(20L)).thenReturn(Optional.of(webDevice));

        assertThrows(AuthApiException.class, () -> service.transfer(1L, 20L));
        verify(ownerRepository, never()).lockByUserId(any());
    }

    @Test
    void transfer_alreadyOwnedByCallingDevice_isANoOp_noEventNoBroadcast() {
        when(deviceRepository.findById(10L)).thenReturn(Optional.of(mobileDevice(10L)));
        when(ownerRepository.lockByUserId(1L)).thenReturn(Optional.of(new MobileStorageOwner(1L, 10L, java.time.LocalDateTime.now())));
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.of(new MobileStorageOwner(1L, 10L, java.time.LocalDateTime.now())));

        MobileStorageStatusResponse result = service.transfer(1L, 10L);

        verify(ownerRepository, never()).save(any());
        verify(historyRepository, never()).save(any());
        verify(securityEventService, never()).record(anyLong(), any(), any(), any(), any(), any(), any());
        verify(relayClient, never()).relayToUser(anyLong(), any(), any());
        assertTrue(result.isOwner());
    }

    @Test
    void transfer_fromAnotherDevice_reassignsOwnership_recordsHistory_notifiesOldDevice() {
        when(deviceRepository.findById(20L)).thenReturn(Optional.of(mobileDevice(20L)));
        MobileStorageOwner existing = new MobileStorageOwner(1L, 10L, java.time.LocalDateTime.now());
        when(ownerRepository.lockByUserId(1L)).thenReturn(Optional.of(existing));
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.of(existing));

        MobileStorageStatusResponse result = service.transfer(1L, 20L);

        assertEquals(20L, existing.getDeviceId()); // row reassigned in place
        verify(ownerRepository).save(existing);

        ArgumentCaptor<MobileStorageHistory> historyCaptor = ArgumentCaptor.forClass(MobileStorageHistory.class);
        verify(historyRepository).save(historyCaptor.capture());
        assertEquals(10L, historyCaptor.getValue().getFromDeviceId());
        assertEquals(20L, historyCaptor.getValue().getToDeviceId());

        verify(securityEventService).record(eq(1L), eq(SecurityEvent.EventType.LOCAL_STORAGE_DEVICE_CHANGED),
                eq(20L), any(), any(), any(), eq(Map.of("fromDeviceId", "10")));

        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(relayClient).relayToUser(eq(1L), eq("/queue/security"), payloadCaptor.capture());
        assertEquals("local_storage.revoked", payloadCaptor.getValue().get("type"));
        assertEquals(10L, payloadCaptor.getValue().get("revokedDeviceId"));
        assertEquals(20L, payloadCaptor.getValue().get("newOwnerDeviceId"));
    }

    @Test
    void transfer_neverClaimedBefore_claimsFreshWithoutABroadcast() {
        // No previous owner to notify — must not call relayClient at all
        // (a null-key relay would be a real bug, not just noise).
        when(deviceRepository.findById(20L)).thenReturn(Optional.of(mobileDevice(20L)));
        when(ownerRepository.lockByUserId(1L)).thenReturn(Optional.empty());
        when(ownerRepository.findByUserId(1L)).thenReturn(Optional.of(new MobileStorageOwner(1L, 20L, java.time.LocalDateTime.now())));

        service.transfer(1L, 20L);

        verify(relayClient, never()).relayToUser(anyLong(), any(), any());
        verify(securityEventService).record(eq(1L), eq(SecurityEvent.EventType.LOCAL_STORAGE_DEVICE_CHANGED),
                eq(20L), any(), any(), any(), eq(Map.of("fromDeviceId", "none")));
    }
}
