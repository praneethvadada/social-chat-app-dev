package com.socialmedia.social.controller;

import com.socialmedia.social.dto.ReportRequest;
import com.socialmedia.social.dto.ReportResponse;
import com.socialmedia.social.service.ReportService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.NoSuchElementException;

@RestController
@RequestMapping("/reports")
@RequiredArgsConstructor
@Tag(name = "Reports", description = "Report users, posts and comments for moderator review")
public class ReportController {

    private final ReportService reportService;

    @PostMapping
    @Operation(summary = "Report a user, post or comment",
            description = "Files a report for moderator review. Reporting the same target again returns the existing report.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Report filed (or already filed)"),
        @ApiResponse(responseCode = "400", description = "Invalid target type or reason, or reporting yourself"),
        @ApiResponse(responseCode = "404", description = "Reported user, post or comment not found"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token missing or invalid")
    })
    public ResponseEntity<ReportResponse> createReport(
            @Valid @RequestBody ReportRequest request,
            @Parameter(hidden = true)
            @RequestAttribute("userId") Long currentUserId) {
        return ResponseEntity.ok(reportService.createReport(currentUserId, request));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> handleBadRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, String>> handleInvalid(MethodArgumentNotValidException e) {
        String message = e.getBindingResult().getFieldErrors().stream()
                .findFirst()
                .map(err -> err.getDefaultMessage())
                .orElse("Invalid report");
        return ResponseEntity.badRequest().body(Map.of("error", message));
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Map<String, String>> handleNotFound(NoSuchElementException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", e.getMessage()));
    }
}
