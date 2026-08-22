package com.socialmedia.auth.service.sms;

import com.twilio.Twilio;
import com.twilio.rest.api.v2010.account.Message;
import com.twilio.type.PhoneNumber;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import com.socialmedia.auth.util.PhoneNumberValidator;

import jakarta.annotation.PostConstruct;

/**
 * Real SMS delivery via Twilio. Credentials come from environment
 * variables / a gitignored application-local.properties override (see
 * application-local.properties.example) — never hardcoded, never committed.
 * Provider failures are translated to a generic message by the caller
 * (PhoneOtpService) — this class only logs the internal detail.
 */
@Service
@ConditionalOnProperty(name = "sms.provider", havingValue = "twilio")
public class TwilioSmsProvider implements SmsProvider {
    private static final Logger log = LoggerFactory.getLogger(TwilioSmsProvider.class);

    @Value("${sms.twilio.account-sid:}")
    private String accountSid;

    @Value("${sms.twilio.auth-token:}")
    private String authToken;

    @Value("${sms.twilio.from-number:}")
    private String fromNumber;

    @PostConstruct
    void init() {
        if (accountSid.isBlank() || authToken.isBlank() || fromNumber.isBlank()) {
            log.warn("sms.provider=twilio but Twilio credentials are not fully configured — OTP sends will fail until sms.twilio.account-sid/auth-token/from-number are set");
            return;
        }
        Twilio.init(accountSid, authToken);
    }

    @Override
    public void sendOtp(String phoneNumberE164, String otp) {
        if (accountSid.isBlank() || authToken.isBlank() || fromNumber.isBlank()) {
            throw new IllegalStateException("SMS provider not configured");
        }
        try {
            Message.creator(
                    new PhoneNumber(phoneNumberE164),
                    new PhoneNumber(fromNumber),
                    "Your verification code is " + otp + ". It expires shortly. Do not share this code."
            ).create();
            log.info("OTP SMS dispatched to {}", PhoneNumberValidator.mask(phoneNumberE164));
        } catch (Exception e) {
            // Never leak provider internals (status codes, account details) to callers.
            log.error("Twilio send failed for {}: {}", PhoneNumberValidator.mask(phoneNumberE164), e.getMessage());
            throw new RuntimeException("Failed to send OTP via SMS provider");
        }
    }
}
