package com.socialmedia.auth.dto;

/**
 * Returned from POST /login (200, not an error) when the account is already
 * active on a DIFFERENT web device — mirrors TwoFactorChallengeResponse's
 * shape/spirit exactly. Confirm-before-kick (post-Phase-10 UX change): the
 * client shows the other device's info and a "log out that device &
 * continue" button; only POST /login/web-session/confirm with this
 * challengeToken actually performs the takeover. See AuthService.finishLogin's
 * own doc comment for why this replaced the previous silent-automatic-kick
 * behavior.
 */
public class WebSessionConflictResponse {

    private final boolean webSessionConflict = true;
    private final String challengeToken;
    private final String platform;
    private final String osName;
    private final String browserName;
    private final String deviceModel;

    public WebSessionConflictResponse(String challengeToken, String platform, String osName,
                                       String browserName, String deviceModel) {
        this.challengeToken = challengeToken;
        this.platform = platform;
        this.osName = osName;
        this.browserName = browserName;
        this.deviceModel = deviceModel;
    }

    public boolean isWebSessionConflict() { return webSessionConflict; }
    public String getChallengeToken() { return challengeToken; }
    public String getPlatform() { return platform; }
    public String getOsName() { return osName; }
    public String getBrowserName() { return browserName; }
    public String getDeviceModel() { return deviceModel; }
}
