package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

/** POST /login/2fa/verify body. deviceInfo is optional, same as /login itself. */
public class TwoFactorLoginVerifyRequest {

    @NotBlank(message = "challengeToken is required")
    private String challengeToken;

    @NotBlank(message = "otp is required")
    private String otp;

    private DeviceInfoRequest deviceInfo;

    public String getChallengeToken() { return challengeToken; }
    public void setChallengeToken(String challengeToken) { this.challengeToken = challengeToken; }

    public String getOtp() { return otp; }
    public void setOtp(String otp) { this.otp = otp; }

    public DeviceInfoRequest getDeviceInfo() { return deviceInfo; }
    public void setDeviceInfo(DeviceInfoRequest deviceInfo) { this.deviceInfo = deviceInfo; }
}
