package com.socialmedia.auth.controller;

import com.socialmedia.auth.dto.DeviceResponse;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.service.DeviceSessionService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * "Currently Logged-In Devices" (Phase 1 of the device/session architecture
 * plan). Requires authentication — neither path is in SecurityConfig's
 * permitAll list, so Spring Security's anyRequest().authenticated() plus
 * JwtAuthenticationFilter's populated SecurityContext enforce it.
 */
@RestController
@RequestMapping("/devices")
@Tag(name = "Devices", description = "Currently logged-in devices and remote session revocation")
public class DeviceController {

    private final DeviceSessionService deviceSessionService;

    public DeviceController(DeviceSessionService deviceSessionService) {
        this.deviceSessionService = deviceSessionService;
    }

    @Operation(summary = "List my devices", description = "Every device this account has ever logged in from, with its current session status.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Device list returned"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @GetMapping
    public ResponseEntity<List<DeviceResponse>> listDevices(
            @RequestAttribute(value = "userId", required = false) Long userId,
            @RequestAttribute(value = "sid", required = false) String sessionToken) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok(deviceSessionService.listDevices(userId, sessionToken));
    }

    @Operation(summary = "Revoke a device's session", description = "Logs that device out remotely — its current session stops working on its next request.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Device session revoked"),
        @ApiResponse(responseCode = "401", description = "Not authenticated"),
        @ApiResponse(responseCode = "404", description = "Device not found or does not belong to this account")
    })
    @PostMapping("/{deviceId}/revoke")
    public ResponseEntity<?> revokeDevice(
            @PathVariable Long deviceId,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        try {
            deviceSessionService.revokeDeviceSession(userId, deviceId, "user_revoked");
            return ResponseEntity.ok(Map.of("message", "Device logged out"));
        } catch (AuthApiException e) {
            throw e;
        }
    }
}
