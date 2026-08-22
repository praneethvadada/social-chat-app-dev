package com.socialmedia.social.service;

import com.socialmedia.social.dto.ShareRequest;
import com.socialmedia.social.entity.Post;
import com.socialmedia.social.entity.Share;
import com.socialmedia.social.repository.PostRepository;
import com.socialmedia.social.repository.ShareRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class ShareService {

    private final ShareRepository shareRepository;
    private final PostRepository postRepository;

    @Transactional
    public void sharePost(ShareRequest request, Long userId) {
        Post post = postRepository.findById(request.getPostId())
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        Share share = new Share();
        share.setUserId(userId);
        share.setPostId(request.getPostId());
        share.setShareNote(request.getShareNote());
        
        shareRepository.save(share);
        
        post.setSharesCount(post.getSharesCount() + 1);
        postRepository.save(post);
    }
}
