package com.socialmedia.social.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Per-status audience entry (S4).
 *
 * Meaning depends on the status's privacyType:
 *   ONLY   -> rows are ALLOW: nobody else may see it
 *   EXCEPT -> rows are DENY : contacts minus these people
 * CONTACTS statuses have no rows at all.
 */
@Entity
@Table(name = "status_audience",
       uniqueConstraints = @UniqueConstraint(name = "uk_status_audience",
               columnNames = {"status_id", "user_id"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class StatusAudience {

    public enum Permission { ALLOW, DENY }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "status_id", nullable = false)
    private Long statusId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private Permission permission = Permission.ALLOW;
}
