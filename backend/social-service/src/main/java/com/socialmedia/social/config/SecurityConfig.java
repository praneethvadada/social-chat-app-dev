package com.socialmedia.social.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @org.springframework.beans.factory.annotation.Autowired
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @org.springframework.beans.factory.annotation.Autowired
    private InternalServiceAuthFilter internalServiceAuthFilter;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/health", "/actuator/**", "/ws/**",
                                "/swagger-ui/**", "/api-docs/**", "/swagger-ui.html",
                                "/profiles/create", "/files/**", "/social/files/**", "/error",
                                "/blocks/internal/**", "/profiles/internal/**",
                                "/push/internal/**").permitAll()  // internal service-to-service calls (chats-service / auth-service)
                .anyRequest().authenticated()
            )
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint((request, response, authException) -> {
                    System.out.println("[SECURITY] Authentication failed for path: " + request.getRequestURI());
                    System.out.println("[SECURITY] Exception: " + authException.getMessage());
                    response.sendError(401, "Unauthorized: " + authException.getMessage());
                })
            )
            // Phase 10 hardening: rejects any caller of /blocks/internal/**,
            // /profiles/internal/** without the shared internal-service
            // secret. Anchored to UsernamePasswordAuthenticationFilter, not
            // JwtAuthenticationFilter.class - addFilterBefore can only order
            // relative to filters Spring Security's own ordering table
            // knows about (see auth-service's identical SecurityConfig for
            // the full explanation of this gotcha).
            .addFilterBefore(internalServiceAuthFilter, UsernamePasswordAuthenticationFilter.class)
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}