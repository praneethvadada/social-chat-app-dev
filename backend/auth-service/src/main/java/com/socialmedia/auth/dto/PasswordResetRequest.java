package com.socialmedia.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public class PasswordResetRequest {
    
    @NotBlank(message = "Email is required")
    @Email(message = "Invalid email format")
    private String email;
    
    @Size(min = 6, message = "Password must be at least 6 characters")
    private String newPassword;

    // Required for POST /password-reset/reset — see AuthService.resetPasswordWithEmail's
    // doc comment for why this is not optional. Unused by POST /password-reset/request,
    // so this can't be @NotBlank at the class level; validated in the service instead.
    private String otp;

    public PasswordResetRequest() {}

    public PasswordResetRequest(String email) {
        this.email = email;
    }

    public PasswordResetRequest(String email, String newPassword) {
        this.email = email;
        this.newPassword = newPassword;
    }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getNewPassword() { return newPassword; }
    public void setNewPassword(String newPassword) { this.newPassword = newPassword; }
    public String getOtp() { return otp; }
    public void setOtp(String otp) { this.otp = otp; }
}
