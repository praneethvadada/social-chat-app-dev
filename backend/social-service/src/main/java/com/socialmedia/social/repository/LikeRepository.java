package com.socialmedia.social.repository;

import com.socialmedia.social.entity.Like;
import com.socialmedia.social.entity.Like.LikeTargetType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface LikeRepository extends JpaRepository<Like, Long> {
    Optional<Like> findByUserIdAndTargetTypeAndTargetId(Long userId, LikeTargetType targetType, Long targetId);
    boolean existsByUserIdAndTargetTypeAndTargetId(Long userId, LikeTargetType targetType, Long targetId);
    Long countByTargetTypeAndTargetId(LikeTargetType targetType, Long targetId);
    void deleteByTargetTypeAndTargetId(LikeTargetType targetType, Long targetId);

    // Get userIds of users who liked a post, most recent first
    @org.springframework.data.jpa.repository.Query("SELECT l.userId FROM Like l WHERE l.targetType = :targetType AND l.targetId = :postId ORDER BY l.createdAt DESC")
    java.util.List<Long> findRecentLikerUserIdsByPostIdAndTargetType(
        @org.springframework.data.repository.query.Param("postId") Long postId,
        @org.springframework.data.repository.query.Param("targetType") Like.LikeTargetType targetType
    );
}
