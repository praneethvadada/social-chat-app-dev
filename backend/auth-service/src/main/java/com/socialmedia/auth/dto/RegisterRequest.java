package com.socialmedia.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
public class RegisterRequest {

    // Found live: nothing previously constrained the CHARACTER SET here —
    // @NotBlank/@Size alone allow spaces, emoji, anything, as long as
    // length is 3-50. A username with a space is a real problem: it's used
    // as a /login identifier (username-based login) and in shareable
    // profile URLs (ApiConfig.webDomain's own doc comment: "/u/<username>"
    // links) — an un-encoded space would break that URL cleanly, and
    // %20-encoding it would just look broken. This mirrors nearly every
    // other app's username rule (letters, digits, underscore, period).
    @NotBlank(message = "Username is required")
    @Size(min = 3, max = 50, message = "Username must be between 3 and 50 characters")
    @Pattern(regexp = "^[a-zA-Z0-9_.]+$", message = "Username can only contain letters, numbers, underscores, and periods — no spaces")
    private String username;

    // Optional now — signup accepts EITHER email OR phoneNumber, never
    // neither, never both. XOR enforcement lives in AuthService.register()
    // since it needs custom messaging @Email/@NotBlank can't express alone.
    @Email(message = "Email should be valid")
    private String email;

    // Raw input (any reasonable format with a country code) — normalized to
    // E.164 by PhoneNumberValidator in AuthService.register().
    private String phoneNumber;

    @NotBlank(message = "Password is required")
    @Size(min = 6, message = "Password must be at least 6 characters")
    private String password;

    @NotBlank(message = "Full name is required")
    @Size(min = 2, max = 100, message = "Full name must be between 2 and 100 characters")
    private String fullName;

    // Optional — absent for not-yet-updated clients (device/session tracking
    // is simply skipped in that case; see AuthService.register()).
    private DeviceInfoRequest deviceInfo;

    // Manual getters/setters to avoid Lombok dependency at runtime
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getPhoneNumber() { return phoneNumber; }
    public void setPhoneNumber(String phoneNumber) { this.phoneNumber = phoneNumber; }
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName; }
    public DeviceInfoRequest getDeviceInfo() { return deviceInfo; }
    public void setDeviceInfo(DeviceInfoRequest deviceInfo) { this.deviceInfo = deviceInfo; }
}
