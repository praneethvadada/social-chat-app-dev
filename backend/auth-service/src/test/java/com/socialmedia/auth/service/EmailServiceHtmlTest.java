package com.socialmedia.auth.service;

import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Phase 9: verifies the actual generated HTML for the security-alert email
 * template — mailSender is never touched by buildSecurityAlertHtml, so this
 * exercises the real template logic without needing a live SMTP connection
 * (which nothing in this test suite has anyway).
 */
class EmailServiceHtmlTest {

    private final EmailService service = new EmailService(null);

    @Test
    void includesTitleMessageAndUsername() {
        // No apostrophe here deliberately — that's covered separately by
        // escapesHtmlInUserSuppliedFields_notXssInjectable below, where an
        // apostrophe/quote being escaped (not appearing verbatim) is the
        // whole point of the assertion.
        String html = service.buildSecurityAlertHtml("praneeth", "New device login",
                "We noticed a sign-in from a device we have not seen before.", Map.of());

        assertTrue(html.contains("New device login"));
        assertTrue(html.contains("We noticed a sign-in from a device we have not seen before."));
        assertTrue(html.contains("Hi praneeth,"));
        assertTrue(html.startsWith("<!DOCTYPE html>"));
        assertTrue(html.trim().endsWith("</html>"));
    }

    @Test
    void rendersDetailRowsInOrder() {
        Map<String, String> details = new LinkedHashMap<>();
        details.put("Device", "Pixel 8");
        details.put("Platform", "ANDROID");

        String html = service.buildSecurityAlertHtml("praneeth", "New device login", "msg", details);

        int deviceIdx = html.indexOf("Pixel 8");
        int platformIdx = html.indexOf("ANDROID");
        assertTrue(deviceIdx > 0);
        assertTrue(platformIdx > deviceIdx, "Device row must render before Platform row (LinkedHashMap order preserved)");
    }

    @Test
    void omitsBlankDetailValues() {
        Map<String, String> details = new LinkedHashMap<>();
        details.put("Device", "Pixel 8");
        details.put("Empty", "");
        details.put("NullLike", null);

        String html = service.buildSecurityAlertHtml("praneeth", "title", "msg", details);

        assertTrue(html.contains("Pixel 8"));
        assertFalse(html.contains(">Empty<"));
        assertFalse(html.contains(">NullLike<"));
    }

    @Test
    void escapesHtmlInUserSuppliedFields_notXssInjectable() {
        // username is not fully attacker-controlled in practice, but device
        // model / metadata values effectively are (client-reported strings
        // stored verbatim) — this is the actual injection surface.
        Map<String, String> details = new LinkedHashMap<>();
        details.put("Device", "<script>alert(1)</script>");

        String html = service.buildSecurityAlertHtml("<b>evil</b>", "title", "msg", details);

        assertFalse(html.contains("<script>"), "raw <script> must never appear in the output");
        assertFalse(html.contains("<b>evil</b>"), "raw markup in username must be escaped");
        assertTrue(html.contains("&lt;script&gt;"));
        assertTrue(html.contains("&lt;b&gt;evil&lt;/b&gt;"));
    }

    @Test
    void nullUsernameFallsBackToGenericGreeting() {
        String html = service.buildSecurityAlertHtml(null, "title", "msg", Map.of());
        assertTrue(html.contains("Hi there,"));
    }

    @Test
    void alwaysIncludesATimeRow() {
        String html = service.buildSecurityAlertHtml("praneeth", "title", "msg", null);
        assertTrue(html.contains(">Time<"));
    }

    @Test
    void escapeHtml_handlesAllFiveSpecialCharacters() {
        assertEquals("&amp;&lt;&gt;&quot;&#39;", service.escapeHtml("&<>\"'"));
    }
}
