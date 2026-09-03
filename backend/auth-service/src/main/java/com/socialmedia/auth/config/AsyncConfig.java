package com.socialmedia.auth.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.concurrent.Executor;

/**
 * Severe, previously-undetected bug found via live testing (post-Phase-10,
 * while wiring the new login-notification push feature): EmailService's
 * security-alert methods have been annotated @Async since Phase 9, but
 * @EnableAsync was never actually configured ANYWHERE in this codebase —
 * Spring silently treats @Async as a no-op without it (a well-known gotcha:
 * it does NOT throw or warn, it just runs the method synchronously as if
 * the annotation weren't there). This meant every "async" security-alert
 * email (NEW_DEVICE, PASSWORD_CHANGED, TWO_FA_ENABLED, etc.) has actually
 * been BLOCKING the request that triggered it this entire time whenever
 * app.mail.enabled=true (the real production config) — invisible in every
 * prior live-testing pass because those all used app.mail.enabled=false
 * (the stdout fallback), which skips the real SMTP network call entirely.
 * Caught only because the new push-notification relay's real network call
 * to Firebase hung for 3+ minutes in testing and made the underlying
 * synchronous-execution problem visible for the first time.
 *
 * A bounded ThreadPoolTaskExecutor (not @EnableAsync's default
 * SimpleAsyncTaskExecutor, which spawns one unbounded new thread per call —
 * a real resource-exhaustion risk if many notification sends hang
 * simultaneously, exactly the failure mode just observed) backs both
 * EmailService's @Async methods and SecurityPushRelayClient's.
 */
@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean(name = "taskExecutor")
    public Executor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(10);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("SecurityNotify-");
        executor.initialize();
        return executor;
    }
}
