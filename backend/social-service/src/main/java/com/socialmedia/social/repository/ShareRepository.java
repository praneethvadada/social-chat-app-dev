package com.socialmedia.social.repository;

import com.socialmedia.social.entity.Share;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface ShareRepository extends JpaRepository<Share, Long> {
    
    Page<Share> findByUserIdOrderByCreatedAtDesc(Long userId, Pageable pageable);
    
    Long countByPostId(Long postId);
    
    void deleteByPostId(Long postId);
}
