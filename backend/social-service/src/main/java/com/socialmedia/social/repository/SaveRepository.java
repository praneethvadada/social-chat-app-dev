package com.socialmedia.social.repository;

import com.socialmedia.social.entity.Save;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface SaveRepository extends JpaRepository<Save, Long> {
    
    Optional<Save> findByUserIdAndPostId(Long userId, Long postId);
    
    boolean existsByUserIdAndPostId(Long userId, Long postId);
    
    Page<Save> findByUserIdOrderByCreatedAtDesc(Long userId, Pageable pageable);
    
    Long countByPostId(Long postId);
    
    void deleteByPostId(Long postId);
}
