package com.socialmedia.auth.repository;

import com.socialmedia.auth.entity.MobileStorageOwner;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import jakarta.persistence.LockModeType;
import java.util.Optional;

@Repository
public interface MobileStorageOwnerRepository extends JpaRepository<MobileStorageOwner, Long> {

    /** Plain read — use for status checks. Do NOT use inside claim/transfer; use the locked variant below instead. */
    Optional<MobileStorageOwner> findByUserId(Long userId);

    /**
     * Row-level lock for the duration of the enclosing transaction — makes
     * concurrent claim/transfer requests for the same user serialize at the
     * database instead of racing in application code (see
     * MobileStorageService.claim/transfer, both @Transactional). Explicit
     * @Query because "findByUserId" is already taken above and Spring Data
     * naming conventions don't have a clean way to derive a second,
     * differently-locked variant of the same query by method name alone.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT m FROM MobileStorageOwner m WHERE m.userId = :userId")
    Optional<MobileStorageOwner> lockByUserId(@Param("userId") Long userId);
}
