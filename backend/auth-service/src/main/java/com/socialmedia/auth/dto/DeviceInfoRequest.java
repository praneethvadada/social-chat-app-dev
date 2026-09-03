package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * Device metadata sent alongside register/login. Nested and optional on the
 * parent request so older/not-yet-updated clients (and every existing test
 * that builds a bare RegisterRequest/LoginRequest) keep working unchanged —
 * AuthService simply skips device/session creation when this is null,
 * falling back to a legacy (unsession-tracked) token. Only deviceId is
 * required; everything else is best-effort metadata.
 */
public class DeviceInfoRequest {

    @NotBlank(message = "deviceId is required")
    private String deviceId;

    // ANDROID | IOS | WEB
    private String platform;

    private String osName;
    private String osVersion;
    private String appVersion;
    private String browserName;
    private String browserVersion;
    private String deviceModel;
    private String pushToken;

    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }

    public String getPlatform() { return platform; }
    public void setPlatform(String platform) { this.platform = platform; }

    public String getOsName() { return osName; }
    public void setOsName(String osName) { this.osName = osName; }

    public String getOsVersion() { return osVersion; }
    public void setOsVersion(String osVersion) { this.osVersion = osVersion; }

    public String getAppVersion() { return appVersion; }
    public void setAppVersion(String appVersion) { this.appVersion = appVersion; }

    public String getBrowserName() { return browserName; }
    public void setBrowserName(String browserName) { this.browserName = browserName; }

    public String getBrowserVersion() { return browserVersion; }
    public void setBrowserVersion(String browserVersion) { this.browserVersion = browserVersion; }

    public String getDeviceModel() { return deviceModel; }
    public void setDeviceModel(String deviceModel) { this.deviceModel = deviceModel; }

    public String getPushToken() { return pushToken; }
    public void setPushToken(String pushToken) { this.pushToken = pushToken; }
}
