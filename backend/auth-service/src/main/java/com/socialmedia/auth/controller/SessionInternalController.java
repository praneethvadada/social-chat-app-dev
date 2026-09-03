package com.socialmedia.auth.controller;

import com.socialmedia.auth.service.DeviceSessionService;
import com.socialmedia.auth.service.DeviceSessionService.SessionCheckResult;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Service-to-service session status lookup. Lets sibling services (Phase 5:
 * chats-service, for both REST and WebSocket) enforce the SAME revocation
 * that JwtAuthenticationFilter already enforces for auth-service's own
 * endpoints - without this, a session revoked here (single-active-web-
 * session takeover, remote device logout) would keep working against
 * chats-service until its JWT naturally expired.
 *
 * Permitted without a user JWT (see SecurityConfig) - matches the existing
 * "/users/*&#47;summary"-style internal endpoints, not a bearer-token flow.
 */
@RestController
@RequestMapping("/internal/sessions")
public class SessionInternalController {

    private final DeviceSessionService deviceSessionService;

    public SessionInternalController(DeviceSessionService deviceSessionService) {
        this.deviceSessionService = deviceSessionService;
    }

    @GetMapping("/{sessionToken}/status")
    public ResponseEntity<Map<String, String>> status(@PathVariable String sessionToken) {
        SessionCheckResult result = deviceSessionService.checkAndTouch(sessionToken);
        return ResponseEntity.ok(Map.of("status", result.name()));
    }
}
