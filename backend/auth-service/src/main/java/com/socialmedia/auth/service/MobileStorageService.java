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
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;

/**
 * Single-active-mobile-device local chat storage authorization (spec
 * §11-15). mobile_storage_owner has exactly one row per user (userId is
 * the PK), so "only one device owns it" is a database-level guarantee, not
 * something this class has to re-verify — see MobileStorageOwner's own doc
 * comment. claim()/transfer() lock that row for the duration of the
 * transaction (MobileStorageOwnerRepository.lockByUserId) so two
 * simultaneous requests from different devices can never both "win".
 */
@Service
public class MobileStorageService {

    private final MobileStorageOwnerRepository ownerRepository;
    private final MobileStorageHistoryRepository historyRepository;
    private final DeviceRepository deviceRepository;
    private final SecurityEventService securityEventService;
    private final ChatsServiceRelayClient relayClient;

    public MobileStorageService(MobileStorageOwnerRepository ownerRepository,
                                 MobileStorageHistoryRepository historyRepository,
                                 DeviceRepository deviceRepository,
                                 SecurityEventService securityEventService,
                                 ChatsServiceRelayClient relayClient) {
        this.ownerRepository = ownerRepository;
        this.historyRepository = historyRepository;
        this.deviceRepository = deviceRepository;
        this.securityEventService = securityEventService;
        this.relayClient = relayClient;
    }

    @Transactional(readOnly = true)
    public MobileStorageStatusResponse getStatus(Long userId, Long callingDeviceId) {
        Optional<MobileStorageOwner> ownerOpt = ownerRepository.findByUserId(userId);
        if (ownerOpt.isEmpty()) {
            return new MobileStorageStatusResponse(false, null);
        }

        MobileStorageOwner owner = ownerOpt.get();
        boolean isOwner = owner.getDeviceId().equals(callingDeviceId);
        MobileStorageStatusResponse.OwnerDeviceInfo info = deviceRepository.findById(owner.getDeviceId())
                .map(d -> new MobileStorageStatusResponse.OwnerDeviceInfo(d.getId(), d.getPlatform(), d.getOsName(), d.getDeviceModel()))
                .orElse(null);
        return new MobileStorageStatusResponse(isOwner, info);
    }

    /** First-ever claim for this account (no prior owner) — a device landing here after login when nobody owns storage yet. Idempotent if this device is already the owner. */
    @Transactional
    public MobileStorageStatusResponse claim(Long userId, Long callingDeviceId) {
        requireMobilePlatform(callingDeviceId);

        Optional<MobileStorageOwner> existing = ownerRepository.lockByUserId(userId);
        if (existing.isPresent()) {
            // Someone already owns it (possibly this same device — fine either way,
            // claim is not the right call to actively take it from someone else; use transfer for that).
            return getStatus(userId, callingDeviceId);
        }

        try {
            ownerRepository.save(new MobileStorageOwner(userId, callingDeviceId, LocalDateTime.now()));
        } catch (DataIntegrityViolationException e) {
            // Lost a race with another first-ever claim for this same user — fine, report whoever actually won.
            return getStatus(userId, callingDeviceId);
        }

        recordHistoryAndEvent(userId, null, callingDeviceId);
        return getStatus(userId, callingDeviceId);
    }

    /** Explicitly takes ownership away from whichever device currently holds it (if any) and gives it to the caller. */
    @Transactional
    public MobileStorageStatusResponse transfer(Long userId, Long callingDeviceId) {
        requireMobilePlatform(callingDeviceId);

        Optional<MobileStorageOwner> existing = ownerRepository.lockByUserId(userId);
        Long previousDeviceId = existing.map(MobileStorageOwner::getDeviceId).orElse(null);

        if (previousDeviceId != null && previousDeviceId.equals(callingDeviceId)) {
            return getStatus(userId, callingDeviceId); // already the owner — no-op
        }

        if (existing.isPresent()) {
            MobileStorageOwner row = existing.get();
            row.setDeviceId(callingDeviceId);
            row.setGrantedAt(LocalDateTime.now());
            ownerRepository.save(row);
        } else {
            ownerRepository.save(new MobileStorageOwner(userId, callingDeviceId, LocalDateTime.now()));
        }

        recordHistoryAndEvent(userId, previousDeviceId, callingDeviceId);

        if (previousDeviceId != null) {
            // Best-effort live notice to the old device, if it's currently
            // connected — see ChatsServiceRelayClient's own doc comment.
            // The old device checks revokedDeviceId against its own id
            // before reacting (this relays to the whole account, not one
            // specific WebSocket session).
            relayClient.relayToUser(userId, "/queue/security", Map.of(
                    "type", "local_storage.revoked",
                    "revokedDeviceId", previousDeviceId,
                    "newOwnerDeviceId", callingDeviceId
            ));
        }

        return getStatus(userId, callingDeviceId);
    }

    private void requireMobilePlatform(Long deviceId) {
        Device device = deviceRepository.findById(deviceId)
                .orElseThrow(() -> new AuthApiException(AuthApiException.ErrorCode.DEVICE_UNKNOWN,
                        "Device not found", HttpStatus.NOT_FOUND));
        String platform = device.getPlatform();
        if (!"ANDROID".equals(platform) && !"IOS".equals(platform)) {
            throw new AuthApiException(AuthApiException.ErrorCode.MOBILE_ONLY_FEATURE,
                    "Local chat storage is only available on mobile devices", HttpStatus.BAD_REQUEST);
        }
    }

    private void recordHistoryAndEvent(Long userId, Long fromDeviceId, Long toDeviceId) {
        MobileStorageHistory history = new MobileStorageHistory();
        history.setUserId(userId);
        history.setFromDeviceId(fromDeviceId);
        history.setToDeviceId(toDeviceId);
        history.setTransferredAt(LocalDateTime.now());
        historyRepository.save(history);

        securityEventService.record(userId, SecurityEvent.EventType.LOCAL_STORAGE_DEVICE_CHANGED, toDeviceId, null,
                null, null, Map.of("fromDeviceId", fromDeviceId == null ? "none" : fromDeviceId.toString()));
    }
}
