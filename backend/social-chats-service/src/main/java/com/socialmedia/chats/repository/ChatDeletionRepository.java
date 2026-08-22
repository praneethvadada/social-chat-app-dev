package com.socialmedia.chats.repository;

import com.socialmedia.chats.entity.ChatDeletion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface ChatDeletionRepository extends JpaRepository<ChatDeletion, Long> {
    
    /**
     * Find deletion record for a specific user and conversation
     */
    Optional<ChatDeletion> findByUserIdAndOtherUserId(Long userId, Long otherUserId);
    
    /**
     * Check if a user has deleted a conversation with another user
     */
    @Query("SELECT COUNT(cd) > 0 FROM ChatDeletion cd WHERE cd.userId = :userId AND cd.otherUserId = :otherUserId")
    boolean hasUserDeletedConversation(@Param("userId") Long userId, @Param("otherUserId") Long otherUserId);
}
