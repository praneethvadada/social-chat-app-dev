package com.socialmedia.auth.util;

import com.google.i18n.phonenumbers.NumberParseException;
import com.google.i18n.phonenumbers.PhoneNumberUtil;
import com.google.i18n.phonenumbers.Phonenumber.PhoneNumber;
import org.springframework.stereotype.Component;

/**
 * Normalizes and validates phone numbers to E.164 (e.g. +919876543210)
 * using Google's libphonenumber rather than a simplistic regex. Used
 * consistently at signup, login, and OTP send/verify — every phone number
 * that reaches storage, a lookup, or an OTP operation has passed through
 * here first.
 */
@Component
public class PhoneNumberValidator {

    private final PhoneNumberUtil phoneNumberUtil = PhoneNumberUtil.getInstance();

    /**
     * Normalizes a raw phone number to E.164. The input must already include
     * a country code (e.g. "+91 98765 43210", "+1 415-555-2671") — this
     * service doesn't guess a default region, since the app has no fixed
     * home country.
     *
     * @throws IllegalArgumentException if the number cannot be parsed or is
     *         not a valid, would-be-diallable number.
     */
    public String normalize(String rawPhoneNumber) {
        if (rawPhoneNumber == null || rawPhoneNumber.trim().isEmpty()) {
            throw new IllegalArgumentException("Phone number is required");
        }
        try {
            PhoneNumber parsed = phoneNumberUtil.parse(rawPhoneNumber.trim(), null);
            if (!phoneNumberUtil.isValidNumber(parsed)) {
                throw new IllegalArgumentException("Invalid phone number");
            }
            return phoneNumberUtil.format(parsed, PhoneNumberUtil.PhoneNumberFormat.E164);
        } catch (NumberParseException e) {
            throw new IllegalArgumentException("Invalid phone number: " + e.getMessage());
        }
    }

    /** Same as {@link #normalize}, but returns null instead of throwing — for format-sniffing (e.g. IdentifierResolver). */
    public String tryNormalize(String rawPhoneNumber) {
        try {
            return normalize(rawPhoneNumber);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    public boolean isValidE164(String rawPhoneNumber) {
        return tryNormalize(rawPhoneNumber) != null;
    }

    /** Masks all but the last 4 digits for safe logging, e.g. "+91******3210". */
    public static String mask(String e164PhoneNumber) {
        if (e164PhoneNumber == null || e164PhoneNumber.length() < 6) {
            return "****";
        }
        String countryPrefix = e164PhoneNumber.substring(0, 3); // e.g. "+91"
        String lastFour = e164PhoneNumber.substring(e164PhoneNumber.length() - 4);
        int maskedLength = e164PhoneNumber.length() - countryPrefix.length() - lastFour.length();
        return countryPrefix + "*".repeat(Math.max(maskedLength, 0)) + lastFour;
    }
}
