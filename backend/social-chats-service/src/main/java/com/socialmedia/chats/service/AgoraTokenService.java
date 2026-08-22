package com.socialmedia.chats.service;

import io.agora.media.RtcTokenBuilder2;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class AgoraTokenService {

    @Value("${agora.app-id:}")
    private String appId;

    @Value("${agora.app-cert:}")
    private String appCert;

    public String getAppId() {
        return appId;
    }

    /**
     * Build an Agora RTC token using AccessToken2 (007) format.
     */
    public String buildRtcToken(String channelName, int uid) {
        if (appId == null || appId.isEmpty() || appCert == null || appCert.isEmpty()) {
            return "";
        }

        int expireInSeconds = 60 * 60; // 1 hour
        RtcTokenBuilder2 tokenBuilder = new RtcTokenBuilder2();
        return tokenBuilder.buildTokenWithUid(appId, appCert, channelName, uid, RtcTokenBuilder2.Role.ROLE_PUBLISHER, expireInSeconds, expireInSeconds);
    }
}
