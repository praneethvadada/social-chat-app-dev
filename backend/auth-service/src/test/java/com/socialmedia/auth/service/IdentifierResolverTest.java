package com.socialmedia.auth.service;

import com.socialmedia.auth.service.IdentifierResolver.IdentifierType;
import com.socialmedia.auth.util.PhoneNumberValidator;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class IdentifierResolverTest {

    private final IdentifierResolver resolver = new IdentifierResolver(new PhoneNumberValidator());

    @Test
    void resolvesEmailAddresses() {
        assertEquals(IdentifierType.EMAIL, resolver.resolve("user@example.com"));
        assertEquals(IdentifierType.EMAIL, resolver.resolve("USER@Example.com"));
    }

    @Test
    void resolvesPhoneNumbers() {
        assertEquals(IdentifierType.PHONE, resolver.resolve("+919876543210"));
        assertEquals(IdentifierType.PHONE, resolver.resolve("+1 415-555-2671"));
    }

    @Test
    void treatsUsernameLikeInputAsInvalid() {
        // Login's `identifier` field is only ever email or phone — a bare
        // username must not resolve to either.
        assertEquals(IdentifierType.INVALID, resolver.resolve("praneeth"));
    }

    @Test
    void rejectsBlankOrNull() {
        assertEquals(IdentifierType.INVALID, resolver.resolve(""));
        assertEquals(IdentifierType.INVALID, resolver.resolve("   "));
        assertEquals(IdentifierType.INVALID, resolver.resolve(null));
    }

    @Test
    void rejectsMalformedPhoneWithoutCountryCode() {
        assertEquals(IdentifierType.INVALID, resolver.resolve("9876543210"));
    }
}
