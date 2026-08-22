package com.socialmedia.chats.repository;

import com.socialmedia.chats.entity.Message;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface MessageRepository extends JpaRepository<Message, Long> {
    
    @Query("SELECT m FROM Message m WHERE (m.senderId = :userId1 AND m.receiverId = :userId2) OR (m.senderId = :userId2 AND m.receiverId = :userId1) ORDER BY m.createdAt DESC")
    Page<Message> findConversation(@Param("userId1") Long userId1, @Param("userId2") Long userId2, Pageable pageable);
    
    @Query("SELECT m FROM Message m WHERE m.receiverId = :userId AND m.isRead = false")
    List<Message> findUnreadMessages(@Param("userId") Long userId);
    
    Long countByReceiverIdAndIsReadFalse(Long receiverId);
    
    @Query("SELECT DISTINCT CASE WHEN m.senderId = :userId THEN m.receiverId ELSE m.senderId END FROM Message m WHERE m.senderId = :userId OR m.receiverId = :userId")
    List<Long> findConversationPartners(@Param("userId") Long userId);
    
    @Query("SELECT m FROM Message m WHERE ((m.senderId = :userId AND m.receiverId = :otherUserId) OR (m.senderId = :otherUserId AND m.receiverId = :userId)) ORDER BY m.createdAt DESC LIMIT 1")
    Message findLastMessageBetween(@Param("userId") Long userId, @Param("otherUserId") Long otherUserId);
    
    @Query("SELECT COUNT(m) FROM Message m WHERE m.receiverId = :userId AND m.senderId = :otherUserId AND m.isRead = false")
    Long countUnreadMessagesBetween(@Param("userId") Long userId, @Param("otherUserId") Long otherUserId);

    @Modifying
    @Query("DELETE FROM Message m WHERE (m.senderId = :userId1 AND m.receiverId = :userId2) OR (m.senderId = :userId2 AND m.receiverId = :userId1)")
    void deleteConversationBetween(@Param("userId1") Long userId1, @Param("userId2") Long userId2);

    @Modifying
    @Query("UPDATE Message m SET m.isRead = true, m.readAt = :readAt WHERE m.id IN :ids")
    void markMessagesReadByIds(@Param("ids") List<Long> ids, @Param("readAt") java.time.LocalDateTime readAt);

    @Modifying
    @Query("UPDATE Message m SET m.isRead = true, m.readAt = :readAt WHERE m.clientMessageId IN :clientIds")
    void markMessagesReadByClientIds(@Param("clientIds") List<String> clientIds, @Param("readAt") java.time.LocalDateTime readAt);

    // G1: group messages live purely in their conversation container
    Page<Message> findByConversationIdOrderByCreatedAtDesc(Long conversationId, Pageable pageable);

    @Query("SELECT m FROM Message m WHERE m.conversationId = :conversationId ORDER BY m.createdAt DESC LIMIT 1")
    Message findLastInConversation(@Param("conversationId") Long conversationId);

    /** Unread count for a group member who has never opened the conversation. */
    @Query("SELECT COUNT(m) FROM Message m WHERE m.conversationId = :conversationId " +
           "AND m.senderId <> :viewerId AND m.isDeleted = false")
    long countUnreadInConversation(@Param("conversationId") Long conversationId, @Param("viewerId") Long viewerId);

    /** Unread count since the member's last read time. */
    @Query("SELECT COUNT(m) FROM Message m WHERE m.conversationId = :conversationId " +
           "AND m.senderId <> :viewerId AND m.isDeleted = false AND m.createdAt > :since")
    long countUnreadInConversationSince(@Param("conversationId") Long conversationId,
                                         @Param("viewerId") Long viewerId,
                                         @Param("since") java.time.LocalDateTime since);

    // ---- G4 ----

    @Query("SELECT m FROM Message m WHERE m.conversationId = :conversationId " +
           "AND m.isPinned = true ORDER BY m.pinnedAt DESC")
    List<Message> findPinned(@Param("conversationId") Long conversationId);

    /** Case-insensitive search within one conversation, excluding tombstones. */
    @Query("SELECT m FROM Message m WHERE m.conversationId = :conversationId " +
           "AND m.isDeleted = false AND m.messageType = 'USER' " +
           "AND LOWER(m.content) LIKE LOWER(CONCAT('%', :query, '%')) " +
           "ORDER BY m.createdAt DESC")
    List<Message> searchInConversation(@Param("conversationId") Long conversationId,
                                       @Param("query") String query);
}
