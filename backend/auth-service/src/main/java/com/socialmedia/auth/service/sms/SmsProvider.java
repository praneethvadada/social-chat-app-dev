package com.socialmedia.auth.service.sms;

/**
 * Abstraction over whatever SMS gateway actually sends the OTP text message.
 * Auth/domain logic (PhoneOtpService) depends only on this interface, never
 * on a concrete provider — swapping providers means adding a new
 * implementation + a config flip, not touching OTP business logic.
 */
public interface SmsProvider {
    void sendOtp(String phoneNumberE164, String otp);
}
