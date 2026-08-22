package com.socialmedia.auth.client;

import com.socialmedia.auth.config.FeignConfig;
import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;

// 🔴 FIX: Reference FeignConfig to include JWT in inter-service calls
@FeignClient(name = "social-service", url = "http://localhost:8082", configuration = FeignConfig.class)
public interface SocialServiceClient {
    
    @PostMapping("/profiles/create")
    void createUserProfile(@RequestBody CreateProfileRequest request);
    
    @DeleteMapping("/profiles/user/{userId}")
    void deleteUserProfile(@PathVariable("userId") Long userId);
    
    class CreateProfileRequest {
        public Long userId;
        public String username;
        public String email;
        public String fullName;
        
        public CreateProfileRequest() {}
        
        public CreateProfileRequest(Long userId, String username, String email, String fullName) {
            this.userId = userId;
            this.username = username;
            this.email = email;
            this.fullName = fullName;
        }
    }
}
