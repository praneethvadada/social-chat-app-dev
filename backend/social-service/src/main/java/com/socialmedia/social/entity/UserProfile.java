package com.socialmedia.social.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "user_profiles")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserProfile {
    
    /**
     * Mirrors auth_db.users.id - assigned, never generated. auth-service owns
     * identity, so a profile row can only exist for a user that already exists.
     */
    @Id
    private Long id;
    
    // userId is an alias for the primary key (see accessors at the bottom).
    @Transient
    private Long userId;
    
    @Column(name = "username", nullable = false, unique = true, length = 50)
    private String username;
    
    @Column(name = "full_name", length = 100)
    private String fullName;
    
    @Column(name = "email", nullable = false, unique = true)
    private String email;
    
    @Column(name = "bio", length = 500)
    private String bio;
    
    @Column(name = "profile_picture", length = 255)
    private String profilePictureUrl;
    
    @Column(name = "cover_photo", length = 255)
    private String coverPhotoUrl;
    
    @Column(name = "location", length = 100)
    private String location;
    
    @Column(name = "website", length = 255)
    private String website;
    
    @Column(name = "date_of_birth")
    private LocalDate dateOfBirth;
    
    @Column(name = "is_private", nullable = false)
    private Boolean isPrivate = false;
    
    @Column(name = "is_verified", nullable = false)
    private Boolean isVerified = false;
    
    @Column(name = "is_online", nullable = false)
    private Boolean isOnline = false;
    
    @Column(name = "last_seen_at")
    private LocalDateTime lastSeenAt;
    
    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;
    
    @UpdateTimestamp
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    /** When the replicated identity fields were last refreshed from auth-service. */
    @Column(name = "synced_at")
    private LocalDateTime syncedAt;
    
    // Getter for userId returns id
    public Long getUserId() {
        return this.id;
    }
    
    // Setter for userId sets id
    public void setUserId(Long userId) {
        this.id = userId;
    }
}
