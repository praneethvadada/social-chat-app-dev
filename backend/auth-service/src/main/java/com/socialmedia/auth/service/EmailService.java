package com.socialmedia.auth.service;

import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

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
    
    @Async
    public void sendPasswordChangedEmail(String toEmail, String username) {
        if (!mailEnabled) {
            log.info("Mail disabled; skipping password changed email to {}", toEmail);
            return;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(fromEmail);
            message.setTo(toEmail);
            message.setSubject("Password Changed - Social Media App");
            
            message.setText(String.format("""
                Hi %s,
                
                Your password has been successfully changed.
                
                If you made this change, you can safely ignore this email.
                
                If you didn't change your password, please contact our support team immediately at support@socialmedia.com
                
                Best regards,
                Social Media Team
                """, username));
            
            mailSender.send(message);
            log.info("Password changed notification sent to: {}", toEmail);
            
        } catch (Exception e) {
            log.error("Failed to send password changed email to: {}", toEmail, e);
        }
    }
    
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
}
