package com.socialmedia.social.repository;

import com.socialmedia.social.entity.BlockedUser;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface BlockedUserRepository extends JpaRepository<BlockedUser, Long> {
    
    boolean existsByBlockerIdAndBlockedId(Long blockerId, Long blockedId);
    
    Optional<BlockedUser> findByBlockerIdAndBlockedId(Long blockerId, Long blockedId);
    
    Page<BlockedUser> findByBlockerIdOrderByCreatedAtDesc(Long blockerId, Pageable pageable);
    
    @Query("SELECT b.blockedId FROM BlockedUser b WHERE b.blockerId = :blockerId")
    List<Long> findBlockedIdsByBlockerId(@Param("blockerId") Long blockerId);
    
    @Query("SELECT b.blockerId FROM BlockedUser b WHERE b.blockedId = :blockedId")
    List<Long> findBlockerIdsByBlockedId(@Param("blockedId") Long blockedId);
    
    long countByBlockerId(Long blockerId);
    
    @Query("SELECT CASE WHEN COUNT(b) = 2 THEN true ELSE false END " +
           "FROM BlockedUser b " +
           "WHERE (b.blockerId = :userId1 AND b.blockedId = :userId2) " +
           "OR (b.blockerId = :userId2 AND b.blockedId = :userId1)")
    boolean areMutuallyBlocked(@Param("userId1") Long userId1, @Param("userId2") Long userId2);
    
    @Query("SELECT CASE WHEN COUNT(b) > 0 THEN true ELSE false END " +
           "FROM BlockedUser b " +
           "WHERE (b.blockerId = :userId1 AND b.blockedId = :userId2) " +
           "OR (b.blockerId = :userId2 AND b.blockedId = :userId1)")
    boolean isEitherBlocked(@Param("userId1") Long userId1, @Param("userId2") Long userId2);
    
    void deleteByBlockerIdAndBlockedId(Long blockerId, Long blockedId);
}
