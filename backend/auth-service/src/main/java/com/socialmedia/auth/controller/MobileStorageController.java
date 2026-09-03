package com.socialmedia.auth.controller;

import com.socialmedia.auth.dto.MobileStorageStatusResponse;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.service.MobileStorageService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Single-active-mobile-device local chat storage authorization (spec
 * §11-15). Requires authentication (not in SecurityConfig's permitAll) and
 * requires the calling token to carry a "deviceId" claim — a legacy token
 * predating device tracking simply can't participate (401), since there's
 * no device identity to attach ownership to.
 */
@RestController
@RequestMapping("/mobile-storage")
@Tag(name = "Mobile Storage", description = "Single-active-device local chat storage ownership")
public class MobileStorageController {

    private final MobileStorageService mobileStorageService;

    public MobileStorageController(MobileStorageService mobileStorageService) {
        this.mobileStorageService = mobileStorageService;
    }

    @Operation(summary = "Check local storage ownership", description = "Whether the calling device currently owns local chat storage, and which device does if not.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Status returned"),
        @ApiResponse(responseCode = "401", description = "Not authenticated or token predates device tracking")
    })
    @GetMapping("/status")
    public ResponseEntity<MobileStorageStatusResponse> status(
            @RequestAttribute(value = "userId", required = false) Long userId,
            @RequestAttribute(value = "deviceId", required = false) Long deviceId) {
        if (userId == null || deviceId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok(mobileStorageService.getStatus(userId, deviceId));
    }

    @Operation(summary = "Claim local storage (first-ever)", description = "Claims ownership when nobody currently owns it. Idempotent if this device already owns it; does not take ownership from another device — use /transfer for that.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Current status after the claim attempt"),
        @ApiResponse(responseCode = "400", description = "MOBILE_ONLY_FEATURE — calling device is not ANDROID/IOS"),
        @ApiResponse(responseCode = "401", description = "Not authenticated or token predates device tracking")
    })
    @PostMapping("/claim")
    public ResponseEntity<?> claim(
            @RequestAttribute(value = "userId", required = false) Long userId,
            @RequestAttribute(value = "deviceId", required = false) Long deviceId) {
        if (userId == null || deviceId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        try {
            return ResponseEntity.ok(mobileStorageService.claim(userId, deviceId));
        } catch (AuthApiException e) {
            throw e;
        }
    }

    @Operation(summary = "Transfer local storage to this device", description = "Explicitly takes ownership away from whichever device currently holds it and grants it to the caller. Notifies the previous device if it's currently connected.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Current status after the transfer"),
        @ApiResponse(responseCode = "400", description = "MOBILE_ONLY_FEATURE — calling device is not ANDROID/IOS"),
        @ApiResponse(responseCode = "401", description = "Not authenticated or token predates device tracking")
    })
    @PostMapping("/transfer")
    public ResponseEntity<?> transfer(
            @RequestAttribute(value = "userId", required = false) Long userId,
            @RequestAttribute(value = "deviceId", required = false) Long deviceId) {
        if (userId == null || deviceId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        try {
            return ResponseEntity.ok(mobileStorageService.transfer(userId, deviceId));
        } catch (AuthApiException e) {
            throw e;
        }
    }
}
