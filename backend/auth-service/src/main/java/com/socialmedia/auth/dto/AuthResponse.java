package com.socialmedia.auth.dto;

public class AuthResponse {
    private String accessToken;
    private String refreshToken;
    private String tokenType = "Bearer";
    private Long userId;
    private String username;
    private String email;
    private String fullName;
    /**
     * Backend-assigned Device row id (distinct from the client's own
     * generated UUID deviceId string) — added so the client can tell
     * account-wide broadcasts like session.revoked/local_storage.revoked
     * apart: those payloads carry THIS numeric id, which the client
     * previously had no way to compare itself against. Null if device info
     * wasn't sent (deviceInfo omitted, or a platform that failed to
     * register for some reason).
     */
    private Long deviceId;

    public AuthResponse() {}

    public AuthResponse(String accessToken, String refreshToken, String tokenType, Long userId, String username, String email, String fullName) {
        this.accessToken = accessToken;
        this.refreshToken = refreshToken;
        this.tokenType = tokenType;
        this.userId = userId;
        this.username = username;
        this.email = email;
        this.fullName = fullName;
    }

    public AuthResponse(String accessToken, String refreshToken, Long userId, String username, String email, String fullName) {
        this(accessToken, refreshToken, "Bearer", userId, username, email, fullName);
    }

    public String getAccessToken() { return accessToken; }
    public void setAccessToken(String accessToken) { this.accessToken = accessToken; }
    public String getRefreshToken() { return refreshToken; }
    public void setRefreshToken(String refreshToken) { this.refreshToken = refreshToken; }
    public String getTokenType() { return tokenType; }
    public void setTokenType(String tokenType) { this.tokenType = tokenType; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName; }
    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }
}
