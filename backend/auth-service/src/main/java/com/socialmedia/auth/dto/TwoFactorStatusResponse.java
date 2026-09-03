package com.socialmedia.auth.dto;

/** GET /security/2fa response, and the return shape after enable/change-method. */
public class TwoFactorStatusResponse {

    private boolean enabled;
    private String method; // "PHONE" | "EMAIL" | null when not enabled

    // What the settings screen needs to know which methods it can even
    // offer — a method with verified=false can't be enabled/switched to
    // (the server rejects it anyway; this just lets the client avoid
    // showing a choice that will always fail). Masked, not the raw
    // email/phone — this is a settings-display value, not an identity read.
    private boolean emailVerified;
    private String maskedEmail;
    private boolean phoneVerified;
    private String maskedPhone;

    public TwoFactorStatusResponse() {
    }

    public TwoFactorStatusResponse(boolean enabled, String method,
                                    boolean emailVerified, String maskedEmail,
                                    boolean phoneVerified, String maskedPhone) {
        this.enabled = enabled;
        this.method = method;
        this.emailVerified = emailVerified;
        this.maskedEmail = maskedEmail;
        this.phoneVerified = phoneVerified;
        this.maskedPhone = maskedPhone;
    }

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }

    public String getMethod() { return method; }
    public void setMethod(String method) { this.method = method; }

    public boolean isEmailVerified() { return emailVerified; }
    public void setEmailVerified(boolean emailVerified) { this.emailVerified = emailVerified; }

    public String getMaskedEmail() { return maskedEmail; }
    public void setMaskedEmail(String maskedEmail) { this.maskedEmail = maskedEmail; }

    public boolean isPhoneVerified() { return phoneVerified; }
    public void setPhoneVerified(boolean phoneVerified) { this.phoneVerified = phoneVerified; }

    public String getMaskedPhone() { return maskedPhone; }
    public void setMaskedPhone(String maskedPhone) { this.maskedPhone = maskedPhone; }
}
