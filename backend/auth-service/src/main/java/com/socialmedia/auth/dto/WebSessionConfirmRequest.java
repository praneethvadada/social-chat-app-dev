package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * POST /login/web-session/confirm body. deviceInfo must be the SAME device
 * info the original /login call sent — this endpoint re-runs the device/
 * session creation finishLogin() does, so it needs the same inputs.
 */
public class WebSessionConfirmRequest {

    @NotBlank(message = "challengeToken is required")
    private String challengeToken;

    private DeviceInfoRequest deviceInfo;

    public String getChallengeToken() { return challengeToken; }
    public void setChallengeToken(String challengeToken) { this.challengeToken = challengeToken; }

    public DeviceInfoRequest getDeviceInfo() { return deviceInfo; }
    public void setDeviceInfo(DeviceInfoRequest deviceInfo) { this.deviceInfo = deviceInfo; }
}
