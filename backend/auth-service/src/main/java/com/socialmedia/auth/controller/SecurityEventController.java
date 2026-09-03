package com.socialmedia.auth.controller;

import com.socialmedia.auth.dto.SecurityEventResponse;
import com.socialmedia.auth.service.SecurityEventService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Phase 8: "Security Activity" — this user's own audit trail. Requires
 * authentication (not in SecurityConfig's permitAll list); there is
 * deliberately no way to read another user's events (userId always comes
 * from the validated JWT, never a path/query parameter).
 */
@RestController
@RequestMapping("/security/events")
@Tag(name = "Security Events", description = "This account's own security audit trail")
public class SecurityEventController {

    private final SecurityEventService securityEventService;

    public SecurityEventController(SecurityEventService securityEventService) {
        this.securityEventService = securityEventService;
    }

    @Operation(summary = "My security activity", description = "Paginated, newest-first log of security-relevant events on this account (logins, new devices, 2FA changes, session revocations, etc).")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Event page returned"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @GetMapping
    public ResponseEntity<Page<SecurityEventResponse>> list(
            @RequestAttribute(value = "userId", required = false) Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        int cappedSize = Math.min(Math.max(size, 1), 50);
        return ResponseEntity.ok(securityEventService.list(userId, PageRequest.of(page, cappedSize)));
    }
}
