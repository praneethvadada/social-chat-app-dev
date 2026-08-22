package com.socialmedia.chats;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Social Chats Service - real-time 1:1 (and later group) messaging, presence,
 * and calling. Owns social_chats_db. Split out of social-service so the
 * WebSocket-heavy, stateful chat workload can scale independently of posts.
 */
@SpringBootApplication
@EnableScheduling
public class ChatsServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(ChatsServiceApplication.class, args);
    }

    /**
     * Force JVM default timezone to UTC so @CreationTimestamp and any
     * LocalDateTime.now() produce UTC, matching what clients expect
     * (they parse zone-less backend timestamps as UTC).
     */
    @jakarta.annotation.PostConstruct
    public void setUtcTimezone() {
        java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"));
    }
}
