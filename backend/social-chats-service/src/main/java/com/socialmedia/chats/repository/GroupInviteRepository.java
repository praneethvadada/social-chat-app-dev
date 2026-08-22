package com.socialmedia.chats.repository;

import com.socialmedia.chats.entity.GroupInvite;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface GroupInviteRepository extends JpaRepository<GroupInvite, Long> {

    Optional<GroupInvite> findByCode(String code);

    @Query("SELECT i FROM GroupInvite i WHERE i.conversationId = :conversationId " +
           "AND i.isActive = true ORDER BY i.createdAt DESC")
    List<GroupInvite> findActive(@Param("conversationId") Long conversationId);
}
