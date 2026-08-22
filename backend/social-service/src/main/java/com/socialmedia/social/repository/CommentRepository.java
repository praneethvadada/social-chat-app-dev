package com.socialmedia.social.repository;

import com.socialmedia.social.entity.Comment;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface CommentRepository extends JpaRepository<Comment, Long> {
    
    Page<Comment> findByPostIdAndParentCommentIdIsNullOrderByCreatedAtDesc(Long postId, Pageable pageable);
    
    List<Comment> findByParentCommentIdOrderByCreatedAtAsc(Long parentCommentId);
    
    Long countByPostId(Long postId);
    
    void deleteByPostId(Long postId);
    
    @Modifying
    @Query("UPDATE Comment c SET c.likesCount = c.likesCount + 1 WHERE c.id = :commentId")
    void incrementLikesCount(@Param("commentId") Long commentId);
    
    @Modifying
    @Query("UPDATE Comment c SET c.likesCount = CASE WHEN c.likesCount > 0 THEN c.likesCount - 1 ELSE 0 END WHERE c.id = :commentId")
    void decrementLikesCount(@Param("commentId") Long commentId);
}
