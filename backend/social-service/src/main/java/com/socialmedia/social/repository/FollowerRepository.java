package com.socialmedia.social.repository;

import com.socialmedia.social.entity.Follower;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface FollowerRepository extends JpaRepository<Follower, Long> {
    
    boolean existsByFollowerIdAndFollowingId(Long followerId, Long followingId);
    
    Optional<Follower> findByFollowerIdAndFollowingId(Long followerId, Long followingId);
    
    Page<Follower> findByFollowingId(Long followingId, Pageable pageable);
    
    Page<Follower> findByFollowerId(Long followerId, Pageable pageable);
    
    @Query("SELECT f.followerId FROM Follower f WHERE f.followingId = :userId")
    List<Long> findFollowerIdsByUserId(@Param("userId") Long userId);
    
    @Query("SELECT f.followingId FROM Follower f WHERE f.followerId = :userId")
    List<Long> findFollowingIdsByUserId(@Param("userId") Long userId);
    
    long countByFollowingId(Long followingId);
    
    long countByFollowerId(Long followerId);
    
    void deleteByFollowerIdAndFollowingId(Long followerId, Long followingId);
    
    void deleteByFollowerIdOrFollowingId(Long followerId, Long followingId);
    
    @Query("SELECT f FROM Follower f WHERE f.followerId = :userId AND " +
           "EXISTS (SELECT f2 FROM Follower f2 WHERE f2.followerId = f.followingId AND f2.followingId = :userId)")
    Page<Follower> findMutualFollowers(@Param("userId") Long userId, Pageable pageable);
    
    @Query("SELECT CASE WHEN COUNT(f) = 2 THEN true ELSE false END FROM Follower f WHERE " +
           "(f.followerId = :userId1 AND f.followingId = :userId2) OR " +
           "(f.followerId = :userId2 AND f.followingId = :userId1)")
    boolean areMutualFollowers(@Param("userId1") Long userId1, @Param("userId2") Long userId2);
}
