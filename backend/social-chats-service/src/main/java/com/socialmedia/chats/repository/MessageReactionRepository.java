package com.socialmedia.chats.repository;

import com.socialmedia.chats.entity.MessageReaction;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface MessageReactionRepository extends JpaRepository<MessageReaction, Long> {

    Optional<MessageReaction> findByMessageIdAndUserId(Long messageId, Long userId);

    List<MessageReaction> findByMessageId(Long messageId);

    /** All reactions for a page of messages, so bubbles render without N queries. */
    List<MessageReaction> findByMessageIdIn(List<Long> messageIds);

    @Query("SELECT r.reaction, COUNT(r) FROM MessageReaction r " +
           "WHERE r.messageId = :messageId GROUP BY r.reaction")
    List<Object[]> countByMessage(@Param("messageId") Long messageId);
}
