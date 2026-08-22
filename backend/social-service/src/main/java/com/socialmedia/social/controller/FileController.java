package com.socialmedia.social.controller;

import com.socialmedia.social.service.S3StorageService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/files")
@RequiredArgsConstructor
public class FileController {

    private final S3StorageService s3StorageService;

    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.s3.region}")
    private String region;

    @PostMapping("/upload")
    public ResponseEntity<Map<String, String>> uploadFile(
            @RequestParam("file") MultipartFile file,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        
        System.out.println("[FILE UPLOAD] Uploading file for userId: " + userId);
        String s3Key = s3StorageService.storeFile(file);
        
        // Construct full S3 URL from the key
        String fullUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
            bucketName, region, s3Key);
        System.out.println("[FILE UPLOAD] Full URL: " + fullUrl);
        
        Map<String, String> response = new HashMap<>();
        response.put("fileUrl", fullUrl);
        
        return ResponseEntity.ok(response);
    }

    @DeleteMapping
    public ResponseEntity<Void> deleteFile(
            @RequestParam("fileUrl") String fileUrl,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        
        System.out.println("[FILE DELETE] Deleting file for userId: " + userId);
        s3StorageService.deleteFile(fileUrl);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/check")
    public ResponseEntity<Map<String, Boolean>> checkFile(
            @RequestParam("fileUrl") String fileUrl) {
        
        boolean exists = s3StorageService.fileExists(fileUrl);
        
        Map<String, Boolean> response = new HashMap<>();
        response.put("exists", exists);
        
        return ResponseEntity.ok(response);
    }
}
