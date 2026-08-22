package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

public class PhoneOtpRequest {

    @NotBlank(message = "Phone number is required")
    private String phoneNumber;

    // PHONE_SIGNUP (unauthenticated, pre-registration) or
    // PHONE_VERIFICATION (authenticated, linking to an existing account).
    @NotBlank(message = "purpose is required")
    private String purpose;

    public String getPhoneNumber() { return phoneNumber; }
    public void setPhoneNumber(String phoneNumber) { this.phoneNumber = phoneNumber; }
    public String getPurpose() { return purpose; }
    public void setPurpose(String purpose) { this.purpose = purpose; }
}
