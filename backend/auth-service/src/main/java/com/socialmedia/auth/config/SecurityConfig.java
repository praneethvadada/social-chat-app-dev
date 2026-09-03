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
    private final InternalServiceAuthFilter internalServiceAuthFilter;

    public SecurityConfig(JwtAuthenticationFilter jwtAuthenticationFilter, InternalServiceAuthFilter internalServiceAuthFilter) {
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
        this.internalServiceAuthFilter = internalServiceAuthFilter;
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
                        "/login/2fa/verify", "/login/2fa/resend",
                        "/login/web-session/confirm",
                        "/auth/send-otp", "/auth/verify-otp", "/auth/resend-otp",
                        "/send-otp", "/verify-otp", "/resend-otp",
                        "/otp/send", "/otp/verify", "/password-reset/**",
                        "/check-availability", "/auth/check-availability",
                        "/error", "/refresh", "/health", "/actuator/**",
                        "/swagger-ui/**", "/api-docs/**", "/swagger-ui.html",
                        // "/account" (DELETE) deliberately NOT here anymore either
                        // (Phase 10 hardening) — it used to verify identity via a
                        // client-supplied {email, password} with no Bearer token
                        // and no 2FA check at all, meaning the single most
                        // destructive action in the app could be performed with
                        // nothing but a leaked password. Same reasoning as "/logout"
                        // below: derives userId from the validated JWT instead, so
                        // it needs anyRequest().authenticated() to actually apply.
                        // "/logout" deliberately NOT here anymore — it used to
                        // trust a spoofable X-User-Id header for identity
                        // (permitAll was required for that to even compile);
                        // it now derives userId from the validated JWT like
                        // every other protected endpoint, so it needs
                        // anyRequest().authenticated() below to actually apply.
                        "/users/*/fcm-token", "/users/*/username",  // Internal service-to-service calls
                        "/users/*/summary", "/users/summaries",     // Internal profile lookups (chats-service)
                        "/users/*/identity",                       // Internal identity write (social-service)
                        "/internal/sessions/*/status",              // Internal session revocation check (chats-service, Phase 5)
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
                // Phase 10 hardening: rejects any caller of /users/**,
                // /internal/sessions/** that doesn't present the shared
                // internal-service secret — see the filter's own doc comment
                // for why these paths needed this despite being permitAll.
                // Anchored to UsernamePasswordAuthenticationFilter (a
                // Spring-Security-recognized filter type), NOT
                // JwtAuthenticationFilter.class — addFilterBefore can only
                // order relative to filters Spring Security's own ordering
                // table knows about; anchoring to a custom filter class
                // throws "does not have a registered order" at context
                // startup. Relative order vs. jwtAuthenticationFilter itself
                // doesn't matter: that filter never rejects a request on its
                // own (see its own doc comment), it only populates request
                // attributes, so either running first is safe.
                .addFilterBefore(internalServiceAuthFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public PasswordEncoder encoder() {
        return new BCryptPasswordEncoder(12);
    }
}
