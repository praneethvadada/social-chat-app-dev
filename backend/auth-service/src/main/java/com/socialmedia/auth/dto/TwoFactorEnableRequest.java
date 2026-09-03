package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

/** POST /security/2fa/enable and /security/2fa/change-method body. */
public class TwoFactorEnableRequest {

    @NotBlank(message = "method is required")
    private String method;

    @NotBlank(message = "otp is required")
    private String otp;

    public String getMethod() { return method; }
    public void setMethod(String method) { this.method = method; }

    public String getOtp() { return otp; }
    public void setOtp(String otp) { this.otp = otp; }
}
