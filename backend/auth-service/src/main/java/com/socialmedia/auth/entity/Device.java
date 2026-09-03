package com.socialmedia.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.LocalDateTime;

/**
 * One row per installed app/browser (an "installation identity"), not per
 * login — a device keeps the same row across many logins/logouts. The
 * client generates and persists deviceId once (a UUID) and sends it on
 * every register/login call; this row is found-or-created and its metadata
 * refreshed each time (OS/app-version drift is expected as the app updates).
 * Distinct from UserSession (one row per login instance, revocable) by
 * design — see the Phase 1 architecture plan.
 */
@Entity
@Table(name = "devices", uniqueConstraints = {
    @UniqueConstraint(columnNames = {"user_id", "device_id"})
})
public class Device {

    public enum Platform {
        ANDROID, IOS, WEB
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    // Client-generated UUID, stable for the life of the install.
    @Column(name = "device_id", nullable = false, length = 64)
    private String deviceId;

    @Column(nullable = false, length = 10)
    private String platform;

    @Column(name = "os_name", length = 50)
    private String osName;

    @Column(name = "os_version", length = 30)
    private String osVersion;

    @Column(name = "app_version", length = 30)
    private String appVersion;

    @Column(name = "browser_name", length = 50)
    private String browserName;

    // Wide on purpose: web's WebBrowserInfo.appVersion is the browser's full
    // appVersion string (in Chrome, effectively the whole User-Agent), not a
    // short version number — a real overflow was hit against a 30-char
    // column during Phase 1 testing. DeviceSessionService also truncates
    // defensively before saving, since this width can't be fully trusted
    // either.
    @Column(name = "browser_version", length = 255)
    private String browserVersion;

    @Column(name = "device_model", length = 100)
    private String deviceModel;

    // Stored for completeness per the architecture plan's device-metadata
    // requirement; not wired into push-send logic in Phase 1 (that's the
    // existing users.fcm_token single-slot mechanism, untouched here).
    @Column(name = "push_token", length = 500)
    private String pushToken;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    public Device() {
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

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

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }
}
