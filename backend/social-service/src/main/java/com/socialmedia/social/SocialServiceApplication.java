package com.socialmedia.social;

import java.util.TimeZone;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

import jakarta.annotation.PostConstruct;

@SpringBootApplication
@EnableScheduling
public class SocialServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(SocialServiceApplication.class, args);
    }

    /**
     * Force the JVM default timezone to UTC so every timestamp source agrees.
     * Several entities use Hibernate's @CreationTimestamp/@UpdateTimestamp,
     * which fill in JVM-local time; on an IST machine that produced wall-clock
     * values 5h30m ahead of what the client expects (it parses zone-less
     * backend timestamps as UTC), showing negative "ago" times in the UI.
     */
    @PostConstruct
    public void setUtcTimezone() {
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
    }
}
