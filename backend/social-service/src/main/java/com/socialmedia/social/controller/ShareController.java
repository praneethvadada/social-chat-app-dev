package com.socialmedia.social.controller;

import com.socialmedia.social.dto.ShareRequest;
import com.socialmedia.social.service.ShareService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/shares")
@RequiredArgsConstructor
public class ShareController {

    private final ShareService shareService;

    @PostMapping
    public ResponseEntity<Void> sharePost(
            @Valid @RequestBody ShareRequest request,
            @RequestAttribute("userId") Long userId) {
        shareService.sharePost(request, userId);
        return ResponseEntity.ok().build();
    }
}
