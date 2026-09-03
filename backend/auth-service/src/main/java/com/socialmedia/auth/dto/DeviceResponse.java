package com.socialmedia.auth.dto;

import java.time.LocalDateTime;

/** GET /devices response shape — one entry per device with its current session status folded in. */
public class DeviceResponse {

    private Long deviceId;
    private String platform;
    private String osName;
    private String osVersion;
    private String appVersion;
    private String browserName;
    private String browserVersion;
    private String deviceModel;
    private String sessionStatus; // ACTIVE | REVOKED | REPLACED | EXPIRED | null (no session on record)
    private LocalDateTime loginTime;
    private LocalDateTime lastActiveAt;
    private boolean isCurrentDevice;

    public DeviceResponse() {
    }

    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }

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

    public String getSessionStatus() { return sessionStatus; }
    public void setSessionStatus(String sessionStatus) { this.sessionStatus = sessionStatus; }

    public LocalDateTime getLoginTime() { return loginTime; }
    public void setLoginTime(LocalDateTime loginTime) { this.loginTime = loginTime; }

    public LocalDateTime getLastActiveAt() { return lastActiveAt; }
    public void setLastActiveAt(LocalDateTime lastActiveAt) { this.lastActiveAt = lastActiveAt; }

    public boolean isCurrentDevice() { return isCurrentDevice; }
    public void setCurrentDevice(boolean currentDevice) { isCurrentDevice = currentDevice; }
}
