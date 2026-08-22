package com.socialmedia.social.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/** One selectable answer on a POLL-type Post. */
@Entity
@Table(name = "poll_options")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class PollOption {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "post_id", nullable = false)
    private Long postId;

    @Column(name = "option_text", nullable = false, length = 200)
    private String optionText;

    @Column(name = "display_order", nullable = false)
    private Integer displayOrder = 0;

    /** Optional: marks this as the poll maker's designated correct answer (quiz-style poll). */
    @Column(name = "is_correct", nullable = false)
    private Boolean isCorrect = false;
}
