package com.socialmedia.social.repository;

import com.socialmedia.social.entity.CloseFriend;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CloseFriendRepository extends JpaRepository<CloseFriend, Long> {

    /**
     * Find close friend relationship between two users
     */
    Optional<CloseFriend> findByUserIdAndCloseFriendUserId(Long userId, Long closeFriendUserId);

    /**
     * Get all close friends of a user
     */
    List<CloseFriend> findByUserId(Long userId);

    /**
     * Check if a user is in close friends list
     */
    boolean existsByUserIdAndCloseFriendUserId(Long userId, Long closeFriendUserId);

    /**
     * Delete a close friend relationship
     */
    void deleteByUserIdAndCloseFriendUserId(Long userId, Long closeFriendUserId);

    /**
     * Get close friend user IDs for a user
     */
    @Query("SELECT cf.closeFriendUserId FROM CloseFriend cf WHERE cf.userId = :userId")
    List<Long> findCloseFriendUserIds(@Param("userId") Long userId);

    /**
     * Count close friends
     */
    long countByUserId(Long userId);

    /**
     * ✅ ADDED: Find users who have a specific user as close friend
     * Used for feed to include Close Friends posts from users who have viewer as close friend
     */
    @Query("SELECT cf.userId FROM CloseFriend cf WHERE cf.closeFriendUserId = :targetUserId")
    List<Long> findUsersWhoHaveAsCloseFriend(@Param("targetUserId") Long targetUserId);
}
