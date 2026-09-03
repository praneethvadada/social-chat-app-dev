package com.socialmedia.auth.service;

import com.socialmedia.auth.dto.TwoFactorStatusResponse;
import com.socialmedia.auth.entity.OtpVerification;
import com.socialmedia.auth.entity.PhoneOtpVerification;
import com.socialmedia.auth.entity.SecurityEvent;
import com.socialmedia.auth.entity.User;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.repository.UserRepository;
import com.socialmedia.auth.util.PhoneNumberValidator;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;

/**
 * 2FA configuration (spec Phase 6) AND the OTP send/verify primitives the
 * Phase 7 login challenge builds on (sendLoginChallengeOtp/
 * verifyLoginChallengeOtp) — AuthService owns the actual login-flow
 * orchestration (challenge-token issuance/validation, finishing login),
 * this class only knows how to reach the account's CONFIGURED method, not
 * anything about login state. Two methods available uniformly regardless
 * of how the account signed up (see the architecture plan's Q2 resolution:
 * login is always password-based here, so there's no "redundant OTP"
 * conflict to special-case around) — PHONE or EMAIL, whichever the account
 * already has verified.
 *
 * Re-authentication design (plan's Security Considerations §15): enabling
 * or switching method requires a FRESH OTP to the target channel — this is
 * the actual security-relevant proof, since it demonstrates the caller
 * currently controls that phone/email, not just that they have a valid
 * session. Disabling requires the current password instead — weakening an
 * account's protection is gated by re-proving account ownership, not
 * channel control (there's no "target channel" for turning it off).
 */
@Service
public class TwoFactorAuthService {

    public enum Method { PHONE, EMAIL }

    private final UserRepository userRepository;
    private final OtpService otpService;
    private final PhoneOtpService phoneOtpService;
    private final PasswordEncoder passwordEncoder;
    private final SecurityEventService securityEventService;

    public TwoFactorAuthService(UserRepository userRepository,
                                 OtpService otpService,
                                 PhoneOtpService phoneOtpService,
                                 PasswordEncoder passwordEncoder,
                                 SecurityEventService securityEventService) {
        this.userRepository = userRepository;
        this.otpService = otpService;
        this.phoneOtpService = phoneOtpService;
        this.passwordEncoder = passwordEncoder;
        this.securityEventService = securityEventService;
    }

    @Transactional(readOnly = true)
    public TwoFactorStatusResponse getStatus(Long userId) {
        User user = getUser(userId);
        boolean emailVerified = user.getEmail() != null && Boolean.TRUE.equals(user.getEmailVerified());
        boolean phoneVerified = user.getPhoneNumber() != null && Boolean.TRUE.equals(user.getPhoneVerified());
        return new TwoFactorStatusResponse(
                Boolean.TRUE.equals(user.getTwoFactorEnabled()), user.getTwoFactorMethod(),
                emailVerified, emailVerified ? maskEmail(user.getEmail()) : null,
                phoneVerified, phoneVerified ? PhoneNumberValidator.mask(user.getPhoneNumber()) : null);
    }

    /** e.g. "jo***@example.com" — enough for the settings screen to confirm "yes, that one", not enough to be a real identity leak. */
    private String maskEmail(String email) {
        int at = email.indexOf('@');
        if (at <= 0) return email;
        String local = email.substring(0, at);
        String visible = local.length() <= 2 ? local : local.substring(0, 2);
        return visible + "***" + email.substring(at);
    }

    /** Sends an OTP to the account's already-verified phone/email, proving the caller currently controls it before letting them (re)configure 2FA onto it. */
    public void sendConfigOtp(Long userId, String methodRaw) {
        User user = getUser(userId);
        Method method = parseMethod(methodRaw);
        if (method == Method.EMAIL) {
            requireVerifiedEmail(user);
            otpService.sendOtp(user.getEmail(), OtpVerification.Purpose.TWO_FACTOR_AUTH);
        } else {
            requireVerifiedPhone(user);
            phoneOtpService.sendOtp(user.getPhoneNumber(), PhoneOtpVerification.Purpose.TWO_FACTOR_AUTH);
        }
    }

    /**
     * Enables 2FA, or switches its method if already enabled — the same
     * operation either way (both require a fresh OTP proving control of the
     * target method), so /enable and /change-method share this
     * implementation; only the security-event type and response semantics
     * differ by prior state.
     */
    @Transactional
    public TwoFactorStatusResponse enableOrChangeMethod(Long userId, String methodRaw, String otp) {
        User user = getUser(userId);
        Method method = parseMethod(methodRaw);

        boolean verified;
        if (method == Method.EMAIL) {
            requireVerifiedEmail(user);
            verified = otpService.verifyOtp(user.getEmail(), otp, OtpVerification.Purpose.TWO_FACTOR_AUTH);
        } else {
            requireVerifiedPhone(user);
            verified = phoneOtpService.verifyOtp(user.getPhoneNumber(), otp, PhoneOtpVerification.Purpose.TWO_FACTOR_AUTH);
        }
        if (!verified) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "Invalid or expired OTP", HttpStatus.BAD_REQUEST);
        }

        boolean wasEnabled = Boolean.TRUE.equals(user.getTwoFactorEnabled());
        String previousMethod = user.getTwoFactorMethod();

        user.setTwoFactorEnabled(true);
        user.setTwoFactorMethod(method.name());
        userRepository.save(user);

        if (wasEnabled && !method.name().equals(previousMethod)) {
            securityEventService.record(userId, SecurityEvent.EventType.TWO_FA_METHOD_CHANGED, null, null, null, null,
                    Map.of("from", previousMethod == null ? "none" : previousMethod, "to", method.name()));
        } else if (!wasEnabled) {
            securityEventService.record(userId, SecurityEvent.EventType.TWO_FA_ENABLED, null, null, null, null,
                    Map.of("method", method.name()));
        }
        // wasEnabled && same method: a no-op re-confirmation - nothing changed, no event needed.

        // Security-notice email deliberately not sent here — HTML/branded
        // security email templates are Phase 9's job (spec's own phase
        // split); the SecurityEvent row above is the audit trail for now.

        return getStatus(userId);
    }

    /** Turns 2FA off. Requires the current password (see class doc comment for why, vs. OTP for enable/change). */
    @Transactional
    public void disable(Long userId, String password) {
        User user = getUser(userId);
        if (!Boolean.TRUE.equals(user.getTwoFactorEnabled())) {
            throw new AuthApiException(AuthApiException.ErrorCode.TWO_FA_NOT_ENABLED,
                    "Two-factor authentication is not enabled", HttpStatus.BAD_REQUEST);
        }
        if (!passwordEncoder.matches(password, user.getPassword())) {
            throw new AuthApiException(AuthApiException.ErrorCode.INVALID_PASSWORD, "Incorrect password", HttpStatus.BAD_REQUEST);
        }

        user.setTwoFactorEnabled(false);
        user.setTwoFactorMethod(null);
        userRepository.save(user);

        securityEventService.record(userId, SecurityEvent.EventType.TWO_FA_DISABLED, null, null, null, null, null);
    }

    /**
     * Phase 7: sends the login-time challenge OTP to whichever method this
     * account has configured (not client-chosen, unlike sendConfigOtp — by
     * login time the choice was already made back in Phase 6). Called by
     * AuthService.login() after the password check succeeds but before any
     * session/device is created.
     */
    public void sendLoginChallengeOtp(User user) {
        if (Method.EMAIL.name().equals(user.getTwoFactorMethod())) {
            otpService.sendOtp(user.getEmail(), OtpVerification.Purpose.TWO_FACTOR_AUTH);
        } else {
            phoneOtpService.sendOtp(user.getPhoneNumber(), PhoneOtpVerification.Purpose.TWO_FACTOR_AUTH);
        }
    }

    /** Phase 7: verifies the login-time challenge OTP against the account's configured method. */
    public boolean verifyLoginChallengeOtp(User user, String otp) {
        if (Method.EMAIL.name().equals(user.getTwoFactorMethod())) {
            return otpService.verifyOtp(user.getEmail(), otp, OtpVerification.Purpose.TWO_FACTOR_AUTH);
        }
        return phoneOtpService.verifyOtp(user.getPhoneNumber(), otp, PhoneOtpVerification.Purpose.TWO_FACTOR_AUTH);
    }

    /** Phase 7: resends the login-time challenge OTP (rate-limited/cooldown behavior inherited from OtpService/PhoneOtpService). */
    public void resendLoginChallengeOtp(User user) {
        if (Method.EMAIL.name().equals(user.getTwoFactorMethod())) {
            otpService.resendOtp(user.getEmail(), OtpVerification.Purpose.TWO_FACTOR_AUTH);
        } else {
            phoneOtpService.resendOtp(user.getPhoneNumber(), PhoneOtpVerification.Purpose.TWO_FACTOR_AUTH);
        }
    }

    private User getUser(Long userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND, "User not found", HttpStatus.NOT_FOUND));
    }

    private Method parseMethod(String raw) {
        try {
            return Method.valueOf(raw == null ? "" : raw.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new AuthApiException(AuthApiException.ErrorCode.INVALID_2FA_METHOD,
                    "method must be PHONE or EMAIL", HttpStatus.BAD_REQUEST);
        }
    }

    private void requireVerifiedEmail(User user) {
        if (user.getEmail() == null || !Boolean.TRUE.equals(user.getEmailVerified())) {
            throw new AuthApiException(AuthApiException.ErrorCode.EMAIL_NOT_VERIFIED,
                    "Add and verify an email before using it for two-factor authentication", HttpStatus.BAD_REQUEST);
        }
    }

    private void requireVerifiedPhone(User user) {
        if (user.getPhoneNumber() == null || !Boolean.TRUE.equals(user.getPhoneVerified())) {
            throw new AuthApiException(AuthApiException.ErrorCode.PHONE_NOT_VERIFIED,
                    "Add and verify a phone number before using it for two-factor authentication", HttpStatus.BAD_REQUEST);
        }
    }
}
