package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

/** POST /security/2fa/send-otp body — {method: "PHONE"|"EMAIL"}. */
public class TwoFactorMethodRequest {

    @NotBlank(message = "method is required")
    private String method;

    public String getMethod() { return method; }
    public void setMethod(String method) { this.method = method; }
}
