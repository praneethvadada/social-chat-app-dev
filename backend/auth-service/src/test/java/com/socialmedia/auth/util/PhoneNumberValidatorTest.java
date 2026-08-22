package com.socialmedia.auth.util;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PhoneNumberValidatorTest {

    private final PhoneNumberValidator validator = new PhoneNumberValidator();

    @ParameterizedTest
    @CsvSource({
        "+919876543210, +919876543210",
        "+91 98765 43210, +919876543210",
        "+14155552671, +14155552671",
        "+1 415-555-2671, +14155552671",
        "+447911123456, +447911123456"
    })
    void normalizesValidNumbersToE164(String raw, String expected) {
        assertEquals(expected, validator.normalize(raw));
    }

    @ParameterizedTest
    @ValueSource(strings = {"9876543210", "0919876543210", "not-a-number", "", "   ", "+1"})
    void rejectsInvalidOrUnqualifiedNumbers(String raw) {
        assertThrows(IllegalArgumentException.class, () -> validator.normalize(raw));
    }

    @Test
    void rejectsNull() {
        assertThrows(IllegalArgumentException.class, () -> validator.normalize(null));
    }

    @Test
    void tryNormalizeReturnsNullInsteadOfThrowing() {
        assertEquals(null, validator.tryNormalize("not-a-number"));
        assertEquals("+919876543210", validator.tryNormalize("+91 98765 43210"));
    }

    @Test
    void isValidE164() {
        assertTrue(validator.isValidE164("+919876543210"));
        assertFalse(validator.isValidE164("9876543210"));
    }

    @Test
    void masksAllButLastFourDigits() {
        assertEquals("+91******3210", PhoneNumberValidator.mask("+919876543210"));
    }

    @Test
    void maskHandlesShortOrNullInputSafely() {
        assertEquals("****", PhoneNumberValidator.mask(null));
        assertEquals("****", PhoneNumberValidator.mask("123"));
    }
}
