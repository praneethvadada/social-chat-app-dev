package io.agora.rtc;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/**
 * Minimal vendored RtcTokenBuilder replacement.
 * NOTE: This is a lightweight implementation that creates a signed token used by our app to authorize channel joins.
 * For full compatibility with Agora AccessToken v2, replace with Agora's official implementation when possible.
 */
public class RtcTokenBuilder {

    public enum Role {
        Role_Publisher,
        Role_Subscriber
    }

    /**
     * Build a simple HMAC-based token. This produces a token string that includes a timestamp and signature.
     * It's sufficient for local testing; for production use the official Agora AccessToken builder.
     */
    public String buildTokenWithUid(String appId, String appCert, String channelName, int uid, Role role, int privilegeExpiredTs) {
        try {
            String payload = String.format("%s:%s:%d:%d:%s", appId, channelName == null ? "" : channelName, uid, privilegeExpiredTs, role.name());
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(appCert.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] sig = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            String sigB64 = Base64.getUrlEncoder().withoutPadding().encodeToString(sig);
            String token = String.format("%s.%d.%s", appId, privilegeExpiredTs, sigB64);
            return token;
        } catch (Exception e) {
            return "";
        }
    }
}
