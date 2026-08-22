package com.socialmedia.social.repository;

import com.socialmedia.social.entity.Post;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PostRepository extends JpaRepository<Post, Long> {

    Page<Post> findByUserIdOrderByCreatedAtDesc(Long userId, Pageable pageable);

    // ✅ FIXED: Query by visibility enum instead of boolean
    Page<Post> findByVisibilityOrderByCreatedAtDesc(Post.PostVisibility visibility, Pageable pageable);

    @Query("SELECT p FROM Post p WHERE p.userId IN :userIds ORDER BY p.createdAt DESC")
    Page<Post> findByUserIdIn(@Param("userIds") List<Long> userIds, Pageable pageable);

    // ✅ ADDED: Get posts visible to a specific user (for explore feed)
    @Query("SELECT p FROM Post p WHERE p.isPublic = true ORDER BY p.createdAt DESC")
    Page<Post> findPublicPosts(Pageable pageable);

    // Hashtag discovery: posts whose content contains "#tag" (case-insensitive).
    // The trailing boundary check (space/end) happens in the service layer,
    // since JPQL LIKE can't express a word boundary — this narrows the SQL
    // scan and the service does the precise match.
    @Query("SELECT p FROM Post p WHERE p.isPublic = true AND LOWER(p.content) LIKE LOWER(CONCAT('%#', :tag, '%')) ORDER BY p.createdAt DESC")
    Page<Post> findByHashtagLike(@Param("tag") String tag, Pageable pageable);

    // ✅ FIXED: Get home feed posts - PUBLIC posts from FOLLOWED users + CLOSE_FRIENDS posts from eligible users
    @Query("SELECT p FROM Post p WHERE " +
           "(p.visibility = :publicStatus AND p.userId IN :publicPostUserIds) OR " +
           "(p.visibility = :closeFriendsStatus AND p.userId IN :closeFriendsUserIds) " +
           "ORDER BY p.createdAt DESC")
    Page<Post> findHomeFeedPosts(
            @Param("publicPostUserIds") List<Long> publicPostUserIds,
            @Param("closeFriendsUserIds") List<Long> closeFriendsUserIds, 
            @Param("publicStatus") Post.PostVisibility publicStatus,
            @Param("closeFriendsStatus") Post.PostVisibility closeFriendsStatus,
            Pageable pageable);

    Long countByUserId(Long userId);

    @Modifying
    @Query("DELETE FROM Post p WHERE p.userId = :userId")
    void deleteByUserProfileId(@Param("userId") Long userId);

    @Modifying
    @Query("UPDATE Post p SET p.likesCount = p.likesCount + 1 WHERE p.id = :postId")
    void incrementLikesCount(@Param("postId") Long postId);

    @Modifying
    @Query("UPDATE Post p SET p.likesCount = CASE WHEN p.likesCount > 0 THEN p.likesCount - 1 ELSE 0 END WHERE p.id = :postId")
    void decrementLikesCount(@Param("postId") Long postId);
}
