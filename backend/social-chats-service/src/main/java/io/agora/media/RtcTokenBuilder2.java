package io.agora.media;

/**
 * RTC token builder using Agora AccessToken2 (version 007).
 */
public class RtcTokenBuilder2 {
    public enum Role {
        ROLE_PUBLISHER(1),
        ROLE_SUBSCRIBER(2);

        public final int initValue;

        Role(int initValue) {
            this.initValue = initValue;
        }
    }

    /**
     * Build an RTC token using a numeric uid.
     */
    public String buildTokenWithUid(String appId, String appCertificate, String channelName, int uid, Role role, int tokenExpire, int privilegeExpire) {
        return buildTokenWithUserAccount(appId, appCertificate, channelName, AccessToken2.getUidStr(uid), role, tokenExpire, privilegeExpire);
    }

    /**
     * Build an RTC token using a user account string.
     */
    public String buildTokenWithUserAccount(String appId, String appCertificate, String channelName, String account, Role role, int tokenExpire, int privilegeExpire) {
        AccessToken2 accessToken = new AccessToken2(appId, appCertificate, tokenExpire);
        AccessToken2.ServiceRtc serviceRtc = new AccessToken2.ServiceRtc(channelName, account);

        serviceRtc.addPrivilegeRtc(AccessToken2.PrivilegeRtc.PRIVILEGE_JOIN_CHANNEL, privilegeExpire);
        if (role == Role.ROLE_PUBLISHER) {
            serviceRtc.addPrivilegeRtc(AccessToken2.PrivilegeRtc.PRIVILEGE_PUBLISH_AUDIO_STREAM, privilegeExpire);
            serviceRtc.addPrivilegeRtc(AccessToken2.PrivilegeRtc.PRIVILEGE_PUBLISH_VIDEO_STREAM, privilegeExpire);
            serviceRtc.addPrivilegeRtc(AccessToken2.PrivilegeRtc.PRIVILEGE_PUBLISH_DATA_STREAM, privilegeExpire);
        }

        accessToken.addService(serviceRtc);

        try {
            return accessToken.build();
        } catch (Exception e) {
            return "";
        }
    }
}
