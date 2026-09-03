package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

/** POST /security/2fa/disable body — current password, not OTP: disabling is the "weakening" action, gated by re-proving account ownership. */
public class TwoFactorDisableRequest {

    @NotBlank(message = "password is required")
    private String password;

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
}
