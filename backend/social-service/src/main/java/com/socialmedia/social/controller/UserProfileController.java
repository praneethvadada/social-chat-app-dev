package com.socialmedia.social.controller;

import com.socialmedia.social.dto.CreateUserProfileRequest;
import com.socialmedia.social.dto.UserProfileRequest;
import com.socialmedia.social.dto.UserProfileResponse;
import com.socialmedia.social.dto.UserSearchResult;
import com.socialmedia.social.service.UserProfileService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/profiles")
@RequiredArgsConstructor
@Tag(name = "User Profiles", description = "View and manage user profiles")
public class UserProfileController {
    
    private final UserProfileService userProfileService;
    
    @GetMapping("/me")
    @Operation(
        summary = "Get my profile",
        description = "Get the profile of the authenticated user"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Profile retrieved successfully"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required"),
        @ApiResponse(responseCode = "404", description = "Profile not found")
    })
    public ResponseEntity<UserProfileResponse> getMyProfile(
            @Parameter(hidden = true) @RequestAttribute("userId") Long userId) {
        
        System.out.println("\n===== GET MY PROFILE ENDPOINT =====");
        System.out.println("[/profiles/me] userId from RequestAttribute: " + userId);
        
        if (userId == null) {
            System.out.println("[/profiles/me] ERROR: userId is null!");
            return ResponseEntity.status(403).build();
        }
        
        System.out.println("[/profiles/me] Calling userProfileService.getProfile()");
        UserProfileResponse profile = userProfileService.getProfile(userId, userId);
        System.out.println("[/profiles/me] Profile retrieved: " + profile.getUsername());
        return ResponseEntity.ok(profile);
    }
    
    @PutMapping("/me")
    @Operation(
        summary = "Update my profile",
        description = "Update the profile information of the authenticated user"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Profile updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid request data"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<UserProfileResponse> updateMyProfile(
            @Parameter(hidden = true) @RequestAttribute("userId") Long userId,
            @Valid @RequestBody UserProfileRequest request) {
        
        System.out.println("\n===== UPDATE PROFILE ENDPOINT =====");
        System.out.println("userId from token: " + userId);
        System.out.println("Request username: " + request.getUsername());
        System.out.println("Request fullName: " + request.getFullName());
        System.out.println("Request bio: " + request.getBio());
        
        UserProfileResponse profile = userProfileService.updateProfile(userId, request);
        
        System.out.println("===== UPDATE PROFILE RESPONSE =====");
        System.out.println("Response username: " + profile.getUsername());
        System.out.println("Response fullName: " + profile.getFullName());
        
        return ResponseEntity.ok(profile);
    }
    
    @GetMapping("/user/{userId}")
    @Operation(
        summary = "Get user profile by ID",
        description = "Get the profile of a specific user by their user ID"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Profile retrieved successfully"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required"),
        @ApiResponse(responseCode = "404", description = "Profile not found")
    })
    public ResponseEntity<UserProfileResponse> getUserProfile(
            @Parameter(description = "User ID") @PathVariable Long userId,
            @Parameter(hidden = true) @RequestAttribute("userId") Long requestingUserId) {
        
        UserProfileResponse profile = userProfileService.getProfile(userId, requestingUserId);
        return ResponseEntity.ok(profile);
    }
    
    @GetMapping("/username/{username}")
    @Operation(
        summary = "Get user profile by username",
        description = "Get the profile of a specific user by their username"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Profile retrieved successfully"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required"),
        @ApiResponse(responseCode = "404", description = "Profile not found")
    })
    public ResponseEntity<UserProfileResponse> getUserProfileByUsername(
            @Parameter(description = "Username") @PathVariable String username,
            @Parameter(hidden = true) @RequestAttribute("userId") Long requestingUserId) {
        
        UserProfileResponse profile = userProfileService.getProfileByUsername(username, requestingUserId);
        return ResponseEntity.ok(profile);
    }
    
    @GetMapping("/search")
    @Operation(
        summary = "Search users",
        description = "Search for users by username or full name. Returns paginated results."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Search completed successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid search query"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Page<UserSearchResult>> searchUsers(
            @Parameter(description = "Search query (username or name)") @RequestParam String query,
            @Parameter(description = "Page number (0-based)") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size") @RequestParam(defaultValue = "20") int size,
            @Parameter(hidden = true) @RequestAttribute("userId") Long requestingUserId) {
        
        Pageable pageable = PageRequest.of(page, size);
        Page<UserSearchResult> results = userProfileService.searchUsers(query, requestingUserId, pageable);
        return ResponseEntity.ok(results);
    }
    
    @GetMapping("/search/public")
    @Operation(
        summary = "Search public users",
        description = "Search for users with public profiles only"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Search completed successfully"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Page<UserSearchResult>> searchPublicUsers(
            @Parameter(description = "Search query") @RequestParam String query,
            @Parameter(description = "Page number (0-based)") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size") @RequestParam(defaultValue = "20") int size,
            @Parameter(hidden = true) @RequestAttribute("userId") Long requestingUserId) {
        
        Pageable pageable = PageRequest.of(page, size);
        Page<UserSearchResult> results = userProfileService.searchPublicUsers(query, requestingUserId, pageable);
        return ResponseEntity.ok(results);
    }
    
    @GetMapping("/suggested")
    @Operation(
        summary = "Get suggested users",
        description = "Get a list of users you might want to follow (users you don't currently follow)"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Suggestions retrieved successfully"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Page<UserSearchResult>> getSuggestedUsers(
            @Parameter(description = "Page number (0-based)") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size") @RequestParam(defaultValue = "20") int size,
            @Parameter(hidden = true) @RequestAttribute("userId") Long requestingUserId) {
        
        Pageable pageable = PageRequest.of(page, size);
        Page<UserSearchResult> results = userProfileService.getSuggestedUsers(requestingUserId, pageable);
        return ResponseEntity.ok(results);
    }
    
    @PostMapping("/create")
    @Operation(
        summary = "Create user profile",
        description = "Create a new user profile (called by auth-service during registration)"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Profile created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid request data")
    })
    public ResponseEntity<UserProfileResponse> createUserProfile(
            @Valid @RequestBody CreateUserProfileRequest request) {
        
        UserProfileResponse profile = userProfileService.createProfile(
            request.getUserId(),
            request.getUsername(),
            request.getEmail(),
            request.getFullName()
        );
        return ResponseEntity.ok(profile);
    }

    @PostMapping("/bulk")
    @Operation(
        summary = "Get user profiles in bulk",
        description = "Get multiple user profiles by their IDs (useful for follower/following lists)"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Profiles retrieved successfully"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<List<UserSearchResult>> getUserProfilesBulk(
            @RequestBody List<Long> userIds,
            @Parameter(hidden = true) @RequestAttribute("userId") Long requestingUserId) {
        
        List<UserSearchResult> results = userProfileService.getUserProfilesByIds(userIds, requestingUserId);
        return ResponseEntity.ok(results);
    }

    @PostMapping("/init")
    @Operation(
        summary = "Initialize user profile",
        description = "Initialize or refresh user profile on first login. Creates profile if doesn't exist."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Profile initialized successfully"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<UserProfileResponse> initializeProfile(
            @Parameter(hidden = true) @RequestAttribute("userId") Long userId) {
        
        UserProfileResponse profile = userProfileService.initializeProfile(userId);
        return ResponseEntity.ok(profile);
    }
    
    @DeleteMapping("/user/{userId}")
    @Operation(
        summary = "Delete user profile",
        description = "Delete a user's profile and all associated data (called by auth-service during account deletion)"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "204", description = "Profile deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Profile not found")
    })
    public ResponseEntity<Void> deleteUserProfile(@PathVariable Long userId) {
        userProfileService.deleteUserProfile(userId);
        return ResponseEntity.noContent().build();
    }

    /**
     * Internal: refresh this service's replica of a user's identity fields.
     * Called by auth-service after a username/full-name change, and usable as a
     * manual self-heal. Service-to-service (permitted without a user JWT).
     */
    @PostMapping("/internal/reconcile/{userId}")
    public ResponseEntity<Void> reconcile(@PathVariable Long userId) {
        userProfileService.reconcileFromAuth(userId);
        return ResponseEntity.ok().build();
    }

    /**
     * A rejected identity change (e.g. username taken) is a client error, not a
     * server fault - surface auth-service's reason with a 409 so the app can
     * show it verbatim.
     */
    @ExceptionHandler(com.socialmedia.social.client.AuthIdentityClient.IdentityRejectedException.class)
    public ResponseEntity<java.util.Map<String, String>> handleIdentityRejected(
            com.socialmedia.social.client.AuthIdentityClient.IdentityRejectedException e) {
        return ResponseEntity.status(org.springframework.http.HttpStatus.CONFLICT)
                .body(java.util.Map.of("error", e.getMessage()));
    }
}
