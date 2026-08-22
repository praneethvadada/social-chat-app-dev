package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

public class LoginRequest {

    // Support both email and username login
    private String email;
    private String username;

    // New: a single field that can be an email OR an E.164 phone number
    // (never username) — resolved by IdentifierResolver. When present, this
    // takes precedence over email/username below. Additive; old clients
    // that only ever send {email,password} or {username,password} are
    // completely unaffected.
    private String identifier;

    @NotBlank(message = "Password is required")
    private String password;

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getIdentifier() { return identifier; }
    public void setIdentifier(String identifier) { this.identifier = identifier; }
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
}
