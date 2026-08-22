package com.socialmedia.social.entity;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "posts")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Post {
    
    /**
     * Post visibility options for Close Friends feature
     */
    public enum PostVisibility {
        PUBLIC,           // Visible to all followers/public
        CLOSE_FRIENDS     // Visible only to close friends
    }

    /** Content type for the "Create something" sheet: Post / Poll / Event. */
    public enum PostType {
        TEXT,
        POLL,
        EVENT
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(nullable = false)
    private Long userId;
    
    @Column(columnDefinition = "TEXT")
    private String content;
    
    @ElementCollection
    @CollectionTable(name = "post_images", joinColumns = @JoinColumn(name = "post_id"))
    @Column(name = "image_url")
    private List<String> imageUrls = new ArrayList<>();
    
    @Column(nullable = false)
    private Boolean isPublic = true;
    
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private PostVisibility visibility = PostVisibility.PUBLIC;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private PostType postType = PostType.TEXT;

    /** EVENT-only: when the event happens. */
    private LocalDateTime eventStartTime;

    /** EVENT-only: free-text location. */
    @Column(length = 200)
    private String eventLocation;

    @Column(nullable = false)
    private Integer likesCount = 0;
    
    @Column(nullable = false)
    private Integer commentsCount = 0;
    
    @Column(nullable = false)
    private Integer sharesCount = 0;
    
    @Column(nullable = false)
    private Integer savesCount = 0;
    
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;
    
    @Column(nullable = false)
    private LocalDateTime updatedAt;
    
    // ✅ ADDED: Ensure visibility and isPublic stay in sync
    public void setVisibility(PostVisibility visibility) {
        this.visibility = visibility;
        this.isPublic = (visibility == PostVisibility.PUBLIC);
    }
    
    // Force UTC timezone on post creation and update
    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now(ZoneId.of("UTC"));
        this.createdAt = now;
        this.updatedAt = now;
        // Ensure consistency on creation
        this.isPublic = (this.visibility == PostVisibility.PUBLIC);
    }
    
    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now(ZoneId.of("UTC"));
        // Ensure consistency on update
        this.isPublic = (this.visibility == PostVisibility.PUBLIC);
    }
}
