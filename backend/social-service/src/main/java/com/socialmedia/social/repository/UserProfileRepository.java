package com.socialmedia.social.repository;

import com.socialmedia.social.entity.UserProfile;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserProfileRepository extends JpaRepository<UserProfile, Long> {
    
    // userId is same as id in users table
    default Optional<UserProfile> findByUserId(Long userId) {
        return findById(userId);
    }
    
    Optional<UserProfile> findByUsername(String username);
    
    Optional<UserProfile> findByEmail(String email);
    
    default boolean existsByUserId(Long userId) {
        return existsById(userId);
    }
    
    boolean existsByUsername(String username);
    
    boolean existsByEmail(String email);
    
    @Query("SELECT u FROM UserProfile u WHERE " +
           "LOWER(u.username) LIKE LOWER(CONCAT('%', :query, '%')) OR " +
           "LOWER(u.fullName) LIKE LOWER(CONCAT('%', :query, '%'))")
    Page<UserProfile> searchUsers(@Param("query") String query, Pageable pageable);
    
    @Query("SELECT u FROM UserProfile u WHERE u.id IN :userIds")
    List<UserProfile> findByUserIdIn(@Param("userIds") List<Long> userIds);

    @Query("SELECT u FROM UserProfile u WHERE u.isOnline = true AND u.lastSeenAt < :cutoff")
    List<UserProfile> findStaleOnlineUsers(@Param("cutoff") java.time.LocalDateTime cutoff);
}
