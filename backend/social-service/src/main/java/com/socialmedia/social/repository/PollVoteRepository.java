package com.socialmedia.social.repository;

import com.socialmedia.social.entity.PollVote;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface PollVoteRepository extends JpaRepository<PollVote, Long> {
    Optional<PollVote> findByPostIdAndUserId(Long postId, Long userId);
    List<PollVote> findByPostId(Long postId);
    Long countByPostIdAndOptionId(Long postId, Long optionId);
}
