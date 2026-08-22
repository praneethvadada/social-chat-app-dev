package com.socialmedia.auth.service;

import com.socialmedia.auth.util.PhoneNumberValidator;
import org.springframework.stereotype.Component;

import java.util.regex.Pattern;

/**
 * Determines whether a login "identifier" is an email address or a phone
 * number, so AuthService.login() doesn't embed this branching logic itself.
 * Deliberately does not resolve to "username" — the identifier field is
 * only ever email or phone per the login flow's design; username login
 * stays on its own separate, pre-existing request field.
 */
@Component
public class IdentifierResolver {

    public enum IdentifierType { EMAIL, PHONE, INVALID }

    // Same practical shape used by jakarta.validation's @Email — good enough
    // to distinguish "this looks like an email" from "this looks like a
    // phone number" without pulling in a full RFC 5322 parser.
    private static final Pattern EMAIL_PATTERN = Pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$");

    private final PhoneNumberValidator phoneNumberValidator;

    public IdentifierResolver(PhoneNumberValidator phoneNumberValidator) {
        this.phoneNumberValidator = phoneNumberValidator;
    }

    public IdentifierType resolve(String identifier) {
        if (identifier == null || identifier.trim().isEmpty()) {
            return IdentifierType.INVALID;
        }
        String trimmed = identifier.trim();
        if (EMAIL_PATTERN.matcher(trimmed).matches()) {
            return IdentifierType.EMAIL;
        }
        if (phoneNumberValidator.isValidE164(trimmed) || trimmed.startsWith("+")) {
            return IdentifierType.PHONE;
        }
        return IdentifierType.INVALID;
    }
}
