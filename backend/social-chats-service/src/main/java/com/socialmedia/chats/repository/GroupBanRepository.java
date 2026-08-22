package com.socialmedia.chats.repository;

import com.socialmedia.chats.entity.GroupBan;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface GroupBanRepository extends JpaRepository<GroupBan, Long> {

    Optional<GroupBan> findByConversationIdAndUserId(Long conversationId, Long userId);

    /** Active, unexpired ban for this user in this group. */
    @Query("SELECT CASE WHEN COUNT(b) > 0 THEN true ELSE false END FROM GroupBan b " +
           "WHERE b.conversationId = :conversationId AND b.userId = :userId " +
           "AND b.status = 'ACTIVE' AND (b.expiresAt IS NULL OR b.expiresAt > :now)")
    boolean isBanned(@Param("conversationId") Long conversationId,
                     @Param("userId") Long userId,
                     @Param("now") LocalDateTime now);

    @Query("SELECT b FROM GroupBan b WHERE b.conversationId = :conversationId " +
           "AND b.status = 'ACTIVE' AND (b.expiresAt IS NULL OR b.expiresAt > :now) " +
           "ORDER BY b.createdAt DESC")
    List<GroupBan> findActiveBans(@Param("conversationId") Long conversationId,
                                  @Param("now") LocalDateTime now);
}
