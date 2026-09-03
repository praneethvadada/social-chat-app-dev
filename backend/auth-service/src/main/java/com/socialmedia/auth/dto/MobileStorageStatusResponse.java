package com.socialmedia.auth.dto;

/** GET /mobile-storage/status response. */
public class MobileStorageStatusResponse {

    private boolean isOwner;
    private OwnerDeviceInfo ownerDevice; // null if no one has ever claimed it yet

    public MobileStorageStatusResponse() {
    }

    public MobileStorageStatusResponse(boolean isOwner, OwnerDeviceInfo ownerDevice) {
        this.isOwner = isOwner;
        this.ownerDevice = ownerDevice;
    }

    public boolean isOwner() { return isOwner; }
    public void setOwner(boolean owner) { isOwner = owner; }

    public OwnerDeviceInfo getOwnerDevice() { return ownerDevice; }
    public void setOwnerDevice(OwnerDeviceInfo ownerDevice) { this.ownerDevice = ownerDevice; }

    public static class OwnerDeviceInfo {
        private Long deviceId;
        private String platform;
        private String osName;
        private String deviceModel;

        public OwnerDeviceInfo() {
        }

        public OwnerDeviceInfo(Long deviceId, String platform, String osName, String deviceModel) {
            this.deviceId = deviceId;
            this.platform = platform;
            this.osName = osName;
            this.deviceModel = deviceModel;
        }

        public Long getDeviceId() { return deviceId; }
        public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }
        public String getPlatform() { return platform; }
        public void setPlatform(String platform) { this.platform = platform; }
        public String getOsName() { return osName; }
        public void setOsName(String osName) { this.osName = osName; }
        public String getDeviceModel() { return deviceModel; }
        public void setDeviceModel(String deviceModel) { this.deviceModel = deviceModel; }
    }
}
