// filepath: c:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\backend\auth-service\src\main\java\com\socialmedia\auth\config\SecurityConfig.java
package com.socialmedia.auth.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;

    public SecurityConfig(JwtAuthenticationFilter jwtAuthenticationFilter) {
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .sessionManagement(manager -> manager.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                // Without this, Spring Security auto-configures its own
                // default POST /logout handling (session-based, redirects to
                // /login?logout) which intercepts the request BEFORE it ever
                // reaches AuthController.logout() — so the real logout logic
                // (clearing the Redis refresh token + FCM token) was
                // silently unreachable. Disabling the built-in logout lets
                // the app's own stateless, JWT-based /logout run instead.
                .logout(logout -> logout.disable())
                .authorizeHttpRequests(requests -> requests
                .requestMatchers(
                        "/register", "/login", "/api/auth/register", "/api/auth/login",
                        "/auth/send-otp", "/auth/verify-otp", "/auth/resend-otp",
                        "/send-otp", "/verify-otp", "/resend-otp",
                        "/otp/send", "/otp/verify", "/password-reset/**",
                        "/check-availability", "/auth/check-availability",
                        "/error", "/refresh", "/health", "/actuator/**",
                        "/swagger-ui/**", "/api-docs/**", "/swagger-ui.html",
                        "/account", "/logout",
                        "/users/*/fcm-token", "/users/*/username",  // Internal service-to-service calls
                        "/users/*/summary", "/users/summaries",     // Internal profile lookups (chats-service)
                        "/users/*/identity",                       // Internal identity write (social-service)
                        // Phone OTP endpoints are path-shared between the unauthenticated
                        // PHONE_SIGNUP purpose and the authenticated PHONE_VERIFICATION
                        // ("link phone to my existing account") purpose — Spring Security
                        // matchers can't branch on request body, so these stay permitAll
                        // and PhoneAuthController itself enforces that PHONE_VERIFICATION
                        // requires a populated "userId" request attribute (set by
                        // JwtAuthenticationFilter below when a valid Bearer token is
                        // present, regardless of permitAll status).
                        "/auth/phone/**",
                        // Always requires auth — enforced in the controller, same reasoning.
                        "/auth/email/link"
                ).permitAll()
                .anyRequest().authenticated()
                )
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public PasswordEncoder encoder() {
        return new BCryptPasswordEncoder(12);
    }
}
