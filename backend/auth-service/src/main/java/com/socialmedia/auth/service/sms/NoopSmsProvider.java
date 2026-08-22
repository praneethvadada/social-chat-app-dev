package com.socialmedia.auth.service.sms;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import com.socialmedia.auth.util.PhoneNumberValidator;

/**
 * Default SMS provider — logs that an OTP would have been sent, without
 * calling any external gateway. Mirrors EmailService's app.mail.enabled=false
 * behavior, so local dev works with zero external SMS config. Never logs
 * the OTP itself (only that one was generated) to stay consistent with the
 * "never log OTP" rule even in this dev-only path — the OTP appears in the
 * DEBUG-level PhoneOtpService log if truly needed locally, not here.
 */
@Service
@ConditionalOnProperty(name = "sms.provider", havingValue = "noop", matchIfMissing = true)
public class NoopSmsProvider implements SmsProvider {
    private static final Logger log = LoggerFactory.getLogger(NoopSmsProvider.class);

    @Override
    public void sendOtp(String phoneNumberE164, String otp) {
        log.info("[SMS disabled - sms.provider=noop] Would send OTP to {}", PhoneNumberValidator.mask(phoneNumberE164));
    }
}
