package com.socialmedia.auth.dto;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * Phase 8: GET /security/events entry. Carries the same raw device fields
 * as DeviceResponse (platform/osName/browserName/deviceModel), not a
 * pre-formatted label, so the client can reuse its existing
 * DeviceSession.displayName-style formatting rather than duplicating that
 * logic server-side. All device fields are null when the event has no
 * associated device (e.g. PASSWORD_CHANGED, TWO_FA_ENABLED today).
 */
public class SecurityEventResponse {

    private Long id;
    private String eventType;
    private LocalDateTime createdAt;
    private String ipAddress;
    private Map<String, Object> metadata;

    private String platform;
    private String osName;
    private String browserName;
    private String deviceModel;

    public SecurityEventResponse() {
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getEventType() { return eventType; }
    public void setEventType(String eventType) { this.eventType = eventType; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public String getIpAddress() { return ipAddress; }
    public void setIpAddress(String ipAddress) { this.ipAddress = ipAddress; }

    public Map<String, Object> getMetadata() { return metadata; }
    public void setMetadata(Map<String, Object> metadata) { this.metadata = metadata; }

    public String getPlatform() { return platform; }
    public void setPlatform(String platform) { this.platform = platform; }

    public String getOsName() { return osName; }
    public void setOsName(String osName) { this.osName = osName; }

    public String getBrowserName() { return browserName; }
    public void setBrowserName(String browserName) { this.browserName = browserName; }

    public String getDeviceModel() { return deviceModel; }
    public void setDeviceModel(String deviceModel) { this.deviceModel = deviceModel; }
}
