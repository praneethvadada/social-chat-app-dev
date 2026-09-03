package com.socialmedia.auth.repository;

import com.socialmedia.auth.entity.ActiveWebSession;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import jakarta.persistence.LockModeType;
import java.util.Optional;

@Repository
public interface ActiveWebSessionRepository extends JpaRepository<ActiveWebSession, Long> {

    /** Plain read — use for status checks. Do NOT use inside claimOrReplace; use the locked variant below instead. */
    Optional<ActiveWebSession> findByUserId(Long userId);

    /**
     * Row-level lock for the duration of the enclosing transaction — makes
     * two near-simultaneous web logins for the same user serialize at the
     * database instead of racing in application code. Mirrors
     * MobileStorageOwnerRepository.lockByUserId exactly, same reasoning.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT a FROM ActiveWebSession a WHERE a.userId = :userId")
    Optional<ActiveWebSession> lockByUserId(@Param("userId") Long userId);
}
