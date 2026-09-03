package com.socialmedia.auth.service;

import jakarta.mail.internet.MimeMessage;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

@Service
public class EmailService {
    private static final Logger log = LoggerFactory.getLogger(EmailService.class);
    
    private final JavaMailSender mailSender;
    
    @Value("${spring.mail.username}")
    private String fromEmail;
    
    @Value("${app.frontend.url:http://localhost:3000}")
    private String frontendUrl;

    @Value("${app.mail.enabled:false}")
    private boolean mailEnabled;

    public EmailService(JavaMailSender mailSender) {
        this.mailSender = mailSender;
    }
    
    @Async
    public void sendPasswordResetEmail(String toEmail, String username, String resetToken) {
        if (!mailEnabled) {
            log.info("Mail disabled; skipping password reset email to {}", toEmail);
            return;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(fromEmail);
            message.setTo(toEmail);
            message.setSubject("Password Reset Request - Social Media App");
            
            String resetLink = frontendUrl + "/reset-password?token=" + resetToken;
            
            message.setText(String.format("""
                Hi %s,
                
                We received a request to reset your password for your Social Media account.
                
                Click the link below to reset your password:
                %s
                
                This link will expire in 1 hour.
                
                If you didn't request a password reset, please ignore this email or contact support if you have concerns.
                
                Best regards,
                Social Media Team
                """, username, resetLink));
            
            mailSender.send(message);
            log.info("Password reset email sent to: {}", toEmail);
            
        } catch (Exception e) {
            log.error("Failed to send password reset email to: {}", toEmail, e);
        }
    }
    
    @Async
    public void sendWelcomeEmail(String toEmail, String username) {
        if (!mailEnabled) {
            log.info("Mail disabled; skipping welcome email to {}", toEmail);
            return;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(fromEmail);
            message.setTo(toEmail);
            message.setSubject("Welcome to Social Media App!");
            
            message.setText(String.format("""
                Hi %s,
                
                Welcome to Social Media App! 🎉
                
                Your account has been successfully created. You can now:
                • Create and share posts
                • Follow other users
                • Like, comment, and interact with content
                • Customize your profile
                • And much more!
                
                Get started by visiting: %s
                
                If you have any questions, feel free to reach out to our support team.
                
                Happy posting!
                Social Media Team
                """, username, frontendUrl));
            
            mailSender.send(message);
            log.info("Welcome email sent to: {}", toEmail);
            
        } catch (Exception e) {
            log.error("Failed to send welcome email to: {}", toEmail, e);
        }
    }
    
    // sendPasswordChangedEmail (plain-text) removed in Phase 9 — its one
    // caller (AuthService.resetPasswordWithEmail) now gets an HTML alert
    // automatically via SecurityEventService.record(), which would have
    // meant emailing the user twice for one password reset otherwise.

    @Async
    public void sendNewFollowerNotification(String toEmail, String username, String followerUsername) {
        if (!mailEnabled) {
            log.info("Mail disabled; skipping follower email to {}", toEmail);
            return;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(fromEmail);
            message.setTo(toEmail);
            message.setSubject("New Follower - Social Media App");
            
            message.setText(String.format("""
                Hi %s,
                
                %s started following you!
                
                Check out their profile: %s/profile/%s
                
                Best regards,
                Social Media Team
                """, username, followerUsername, frontendUrl, followerUsername));
            
            mailSender.send(message);
            log.info("New follower notification sent to: {}", toEmail);
            
        } catch (Exception e) {
            log.error("Failed to send follower notification to: {}", toEmail, e);
        }
    }
    
    @Async
    public void sendPostLikedNotification(String toEmail, String username, String likerUsername) {
        if (!mailEnabled) {
            log.info("Mail disabled; skipping post liked email to {}", toEmail);
            return;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(fromEmail);
            message.setTo(toEmail);
            message.setSubject("Someone Liked Your Post - Social Media App");
            
            message.setText(String.format("""
                Hi %s,
                
                %s liked your post!
                
                Check your notifications: %s/notifications
                
                Best regards,
                Social Media Team
                """, username, likerUsername, frontendUrl));
            
            mailSender.send(message);
            log.info("Post liked notification sent to: {}", toEmail);
            
        } catch (Exception e) {
            log.error("Failed to send post liked notification to: {}", toEmail, e);
        }
    }
    
    @Async
    public void sendNewCommentNotification(String toEmail, String username, String commenterUsername, String commentText) {
        if (!mailEnabled) {
            log.info("Mail disabled; skipping comment email to {}", toEmail);
            return;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(fromEmail);
            message.setTo(toEmail);
            message.setSubject("New Comment on Your Post - Social Media App");
            
            String truncatedComment = commentText.length() > 100 
                ? commentText.substring(0, 100) + "..." 
                : commentText;
            
            message.setText(String.format("""
                Hi %s,
                
                %s commented on your post:
                "%s"
                
                View the full comment: %s/notifications
                
                Best regards,
                Social Media Team
                """, username, commenterUsername, truncatedComment, frontendUrl));
            
            mailSender.send(message);
            log.info("New comment notification sent to: {}", toEmail);
            
        } catch (Exception e) {
            log.error("Failed to send comment notification to: {}", toEmail, e);
        }
    }
    
    @Async
    public void sendOtpEmail(String toEmail, String otp) {
        if (!mailEnabled) {
            log.warn("⚠️ EMAIL DISABLED - OTP would be sent to {}: {}", toEmail, otp);
            System.out.println("\n" + "=".repeat(60));
            System.out.println("⚠️  EMAIL SERVICE DISABLED");
            System.out.println("=".repeat(60));
            System.out.println("OTP for " + toEmail + ": " + otp);
            System.out.println("To enable email, set: app.mail.enabled=true");
            System.out.println("And configure SMTP settings in application.properties");
            System.out.println("=".repeat(60) + "\n");
            return;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(fromEmail);
            message.setTo(toEmail);
            message.setSubject("Your Email Verification Code - Social Chat App");
            
            message.setText(String.format("""
                Hi,
                
                Your email verification code is:
                
                %s
                
                This code will expire in 10 minutes.
                
                If you didn't request this code, please ignore this email or contact support if you have concerns.
                
                Do not share this code with anyone.
                
                Best regards,
                Social Chat Team
                """, otp));
            
            mailSender.send(message);
            log.info("OTP email sent to: {}", toEmail);
            
        } catch (Exception e) {
            log.error("Failed to send OTP email to: {}", toEmail, e);
        }
    }
    
    @Async
    public void sendPasswordResetOtpEmail(String toEmail, String username) {
        if (!mailEnabled) {
            log.info("Mail disabled; skipping password reset OTP email to {}", toEmail);
            return;
        }
        try {
            // Generate OTP using OtpService through service layer
            // This method triggers OTP generation in the calling service
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(fromEmail);
            message.setTo(toEmail);
            message.setSubject("Password Reset OTP - Social Chat App");
            
            message.setText(String.format("""
                Hi %s,
                
                We received a request to reset your password.
                
                An OTP has been sent to your email. Please check your inbox for the verification code.
                
                The OTP will expire in 10 minutes.
                
                If you didn't request a password reset, please ignore this email or contact support if you have concerns.
                
                Best regards,
                Social Chat Team
                """, username));
            
            mailSender.send(message);
            log.info("Password reset OTP notification sent to: {}", toEmail);

        } catch (Exception e) {
            log.error("Failed to send password reset OTP email to: {}", toEmail, e);
        }
    }

    /**
     * Phase 9: every security-sensitive account change (spec §29's list —
     * new device, password/email/phone changed, 2FA enable/disable/method
     * change, device logged out, new web session, chat-storage device
     * changed) gets an HTML alert through this ONE method, called from
     * SecurityEventService.record() rather than scattered across each
     * individual flow — every prior email in this class is plain
     * SimpleMailMessage text; this is the first HTML one, per the user's
     * own confirmed preference (architecture plan Q6: "Good Email HTML
     * template only"). No new template-engine dependency — inline HTML +
     * CSS in a Java text block, matching this class's existing house style
     * of building message bodies directly rather than introducing
     * Thymeleaf/FreeMarker for a handful of templates.
     *
     * @param details ordered key/value pairs shown as a table (device,
     *                platform, time, etc.) — omit anything not relevant to
     *                this particular event rather than padding with nulls.
     */
    @Async
    public void sendSecurityAlertEmail(String toEmail, String username, String title, String message, Map<String, String> details) {
        if (!mailEnabled) {
            log.info("Mail disabled; skipping security alert '{}' to {}", title, toEmail);
            return;
        }
        try {
            MimeMessage mimeMessage = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(mimeMessage, false, "UTF-8");
            helper.setFrom(fromEmail);
            helper.setTo(toEmail);
            helper.setSubject(title + " - Social Chat App");
            helper.setText(buildSecurityAlertHtml(username, title, message, details), true);

            mailSender.send(mimeMessage);
            log.info("Security alert '{}' sent to: {}", title, toEmail);
        } catch (Exception e) {
            log.error("Failed to send security alert '{}' to: {}", title, toEmail, e);
        }
    }

    // Package-private (not private) so EmailServiceHtmlTest can verify the
    // generated markup directly instead of only exercising this indirectly
    // through a real SMTP send.
    String buildSecurityAlertHtml(String username, String title, String message, Map<String, String> details) {
        String safeUsername = escapeHtml(username == null ? "there" : username);
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("MMM d, yyyy 'at' h:mm a")) + " UTC";

        Map<String, String> rows = new LinkedHashMap<>();
        rows.put("Time", timestamp);
        if (details != null) rows.putAll(details);

        StringBuilder detailRows = new StringBuilder();
        for (Map.Entry<String, String> entry : rows.entrySet()) {
            if (entry.getValue() == null || entry.getValue().isBlank()) continue;
            detailRows.append("""
                <tr>
                  <td style="padding:6px 0;color:#6b7280;font-size:13px;width:110px;">%s</td>
                  <td style="padding:6px 0;color:#111827;font-size:13px;font-weight:600;">%s</td>
                </tr>
                """.formatted(escapeHtml(entry.getKey()), escapeHtml(entry.getValue())));
        }

        return """
            <!DOCTYPE html>
            <html>
            <body style="margin:0;padding:24px;background:#f3f4f6;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;">
              <table role="presentation" width="100%%" style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:14px;overflow:hidden;box-shadow:0 2px 10px rgba(0,0,0,0.06);">
                <tr>
                  <td style="background:#059669;padding:22px 24px;">
                    <span style="color:#ffffff;font-size:18px;font-weight:700;">Social Chat</span>
                  </td>
                </tr>
                <tr>
                  <td style="padding:28px 24px 8px 24px;">
                    <h1 style="margin:0 0 12px 0;color:#111827;font-size:19px;">%s</h1>
                    <p style="margin:0 0 18px 0;color:#374151;font-size:14px;line-height:1.6;">Hi %s,</p>
                    <p style="margin:0 0 18px 0;color:#374151;font-size:14px;line-height:1.6;">%s</p>
                    <table role="presentation" width="100%%" style="border-top:1px solid #e5e7eb;border-bottom:1px solid #e5e7eb;margin:0 0 18px 0;">
                      %s
                    </table>
                    <p style="margin:0;color:#6b7280;font-size:13px;line-height:1.6;">If this wasn't you, secure your account now: change your password and review your active sessions under Settings → Security.</p>
                  </td>
                </tr>
                <tr>
                  <td style="background:#f9fafb;padding:16px 24px;text-align:center;">
                    <span style="color:#9ca3af;font-size:12px;">This is an automated security notice from Social Chat. Do not reply to this email.</span>
                  </td>
                </tr>
              </table>
            </body>
            </html>
            """.formatted(escapeHtml(title), safeUsername, escapeHtml(message), detailRows.toString());
    }

    String escapeHtml(String value) {
        if (value == null) return "";
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;").replace("'", "&#39;");
    }
}
