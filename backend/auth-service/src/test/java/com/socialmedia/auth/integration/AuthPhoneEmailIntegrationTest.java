package com.socialmedia.auth.integration;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.socialmedia.auth.client.SocialServiceClient;
import com.socialmedia.auth.entity.PhoneOtpVerification;
import com.socialmedia.auth.repository.PhoneOtpVerificationRepository;
import com.socialmedia.auth.repository.UserRepository;
import com.socialmedia.auth.service.EmailService;
import com.socialmedia.auth.service.sms.SmsProvider;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;

import static org.hamcrest.Matchers.notNullValue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doNothing;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end flows against the real (locally running) MySQL dev database —
 * no Testcontainers/H2 exist in this project, so this reuses the same
 * datasource application.properties already points at, wrapped in
 * @Transactional so every test's writes roll back automatically and never
 * pollute real data. External side effects (SMS, email, the social-service
 * Feign call) are mocked so tests are fast, deterministic, and don't depend
 * on those services actually running or credentials being configured.
 *
 * Covers the three flows from the feature spec:
 * Flow A: email signup -> verify -> add phone -> verify -> login both ways -> refresh -> logout
 * Flow B: phone signup -> verify -> add email -> verify -> login both ways -> refresh -> logout
 * Flow C: wrong OTP -> expires -> resend -> verify -> complete signup
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
class AuthPhoneEmailIntegrationTest {

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private PhoneOtpVerificationRepository phoneOtpVerificationRepository;
    @Autowired private UserRepository userRepository;

    @MockBean private SmsProvider smsProvider;
    @MockBean private EmailService emailService;
    @MockBean private SocialServiceClient socialServiceClient;

    private String uniqueEmail() { return "itest-" + UUID.randomUUID() + "@example.com"; }
    private String uniquePhone() {
        // +91 9xxxxxxxxx, deterministic-enough to be unique per test run
        return "+91" + (9000000000L + Math.abs(UUID.randomUUID().getMostSignificantBits() % 999999999L));
    }

    /** Directly reads back the plaintext OTP the (mocked) EmailService was asked to send. */
    private String captureEmailOtp(String email) throws Exception {
        mockMvc.perform(post("/send-otp").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("email", email))))
                .andExpect(status().isOk());

        org.mockito.ArgumentCaptor<String> captor = org.mockito.ArgumentCaptor.forClass(String.class);
        org.mockito.Mockito.verify(emailService, org.mockito.Mockito.atLeastOnce()).sendOtpEmail(org.mockito.ArgumentMatchers.eq(email), captor.capture());
        return captor.getValue();
    }

    /** Directly reads back the plaintext OTP the (mocked) SmsProvider was asked to send. */
    private String capturePhoneOtp(String phone, String purpose, boolean authHeader, String token) throws Exception {
        var request = post("/auth/phone/send-otp").contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("phoneNumber", phone, "purpose", purpose)));
        if (authHeader) request = request.header("Authorization", "Bearer " + token);

        mockMvc.perform(request).andExpect(status().isOk());

        org.mockito.ArgumentCaptor<String> captor = org.mockito.ArgumentCaptor.forClass(String.class);
        org.mockito.Mockito.verify(smsProvider, org.mockito.Mockito.atLeastOnce()).sendOtp(org.mockito.ArgumentMatchers.eq(phone), captor.capture());
        return captor.getValue();
    }

    @Test
    void flowA_emailSignup_addPhone_loginBothWays_refresh_logout() throws Exception {
        doNothing().when(socialServiceClient).createUserProfile(any());
        String email = uniqueEmail();
        String phone = uniquePhone();
        String username = "itestA" + System.nanoTime();

        // Signup with Email -> Email Verification
        String emailOtp = captureEmailOtp(email);
        mockMvc.perform(post("/verify-otp").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("email", email, "otp", emailOtp))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        String registerBody = objectMapper.writeValueAsString(Map.of(
                "username", username, "password", "Password@123", "email", email, "fullName", "Flow A"));
        String registerResponse = mockMvc.perform(post("/register").contentType(MediaType.APPLICATION_JSON).content(registerBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken", notNullValue()))
                .andReturn().getResponse().getContentAsString();
        Map<String, Object> tokens = objectMapper.readValue(registerResponse, Map.class);
        String accessToken = (String) tokens.get("accessToken");
        String refreshToken = (String) tokens.get("refreshToken");
        Number userId = (Number) tokens.get("userId");

        // Add Phone -> Send OTP -> Verify OTP (authenticated linking)
        String phoneOtp = capturePhoneOtp(phone, "PHONE_VERIFICATION", true, accessToken);
        mockMvc.perform(post("/auth/phone/verify-otp").contentType(MediaType.APPLICATION_JSON)
                        .header("Authorization", "Bearer " + accessToken)
                        .content(objectMapper.writeValueAsString(Map.of("phoneNumber", phone, "otp", phoneOtp, "purpose", "PHONE_VERIFICATION"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.verified").value(true));

        // Login with Email
        mockMvc.perform(post("/login").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("identifier", email, "password", "Password@123"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId").value(userId.intValue()));

        // Login with Phone
        mockMvc.perform(post("/login").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("identifier", phone, "password", "Password@123"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId").value(userId.intValue()));

        // Refresh Token
        mockMvc.perform(post("/refresh").param("refreshToken", refreshToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken", notNullValue()));

        // Logout — derives identity from the Bearer token now (the old
        // X-User-Id-header path was a spoofable-identity bug, fixed in
        // Phase 1 of the device/session work).
        mockMvc.perform(post("/logout").header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk());
    }

    @Test
    void flowB_phoneSignup_addEmail_loginBothWays_refresh_logout() throws Exception {
        doNothing().when(socialServiceClient).createUserProfile(any());
        String phone = uniquePhone();
        String email = uniqueEmail();
        String username = "itestB" + System.nanoTime();

        // Signup with Phone -> Phone OTP Verification (purpose=PHONE_SIGNUP, unauthenticated)
        String phoneOtp = capturePhoneOtp(phone, "PHONE_SIGNUP", false, null);
        mockMvc.perform(post("/auth/phone/verify-otp").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("phoneNumber", phone, "otp", phoneOtp, "purpose", "PHONE_SIGNUP"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.verified").value(true));

        String registerBody = objectMapper.writeValueAsString(Map.of(
                "username", username, "password", "Password@123", "phoneNumber", phone, "fullName", "Flow B"));
        String registerResponse = mockMvc.perform(post("/register").contentType(MediaType.APPLICATION_JSON).content(registerBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken", notNullValue()))
                .andReturn().getResponse().getContentAsString();
        Map<String, Object> tokens = objectMapper.readValue(registerResponse, Map.class);
        String accessToken = (String) tokens.get("accessToken");
        String refreshToken = (String) tokens.get("refreshToken");
        Number userId = (Number) tokens.get("userId");

        // Add Email -> Email Verification (existing send-otp, then the new authenticated /auth/email/link)
        String emailOtp = captureEmailOtp(email);
        mockMvc.perform(post("/auth/email/link").contentType(MediaType.APPLICATION_JSON)
                        .header("Authorization", "Bearer " + accessToken)
                        .content(objectMapper.writeValueAsString(Map.of("email", email, "otp", emailOtp))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.verified").value(true));

        // Login with Phone
        mockMvc.perform(post("/login").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("identifier", phone, "password", "Password@123"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId").value(userId.intValue()));

        // Login with Email
        mockMvc.perform(post("/login").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("identifier", email, "password", "Password@123"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId").value(userId.intValue()));

        // Refresh Token
        mockMvc.perform(post("/refresh").param("refreshToken", refreshToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken", notNullValue()));

        // Logout — derives identity from the Bearer token now (the old
        // X-User-Id-header path was a spoofable-identity bug, fixed in
        // Phase 1 of the device/session work).
        mockMvc.perform(post("/logout").header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk());
    }

    @Test
    void flowC_wrongOtp_thenExpired_thenResend_thenVerify_thenRegister() throws Exception {
        doNothing().when(socialServiceClient).createUserProfile(any());
        String phone = uniquePhone();
        String username = "itestC" + System.nanoTime();

        // Wrong OTP
        capturePhoneOtp(phone, "PHONE_SIGNUP", false, null);
        mockMvc.perform(post("/auth/phone/verify-otp").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("phoneNumber", phone, "otp", "000000", "purpose", "PHONE_SIGNUP"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errorCode").value("OTP_INVALID"));

        // OTP expires — force it directly (waiting 5 real minutes isn't practical in a test)
        PhoneOtpVerification row = phoneOtpVerificationRepository
                .findTopByPhoneNumberAndPurposeOrderByCreatedAtDesc(phone, "PHONE_SIGNUP").orElseThrow();
        row.setExpiresAt(LocalDateTime.now().minusSeconds(1));
        phoneOtpVerificationRepository.save(row);

        mockMvc.perform(post("/auth/phone/verify-otp").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("phoneNumber", phone, "otp", "000000", "purpose", "PHONE_SIGNUP"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errorCode").value("OTP_EXPIRED"));

        // Request new OTP — back-date the expired row's createdAt so the
        // resend cooldown (60s) doesn't also block this in the same test run.
        row.setCreatedAt(LocalDateTime.now().minusMinutes(5));
        phoneOtpVerificationRepository.save(row);

        var resendRequest = post("/auth/phone/resend-otp").contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("phoneNumber", phone, "purpose", "PHONE_SIGNUP")));
        mockMvc.perform(resendRequest).andExpect(status().isOk());

        org.mockito.ArgumentCaptor<String> captor = org.mockito.ArgumentCaptor.forClass(String.class);
        org.mockito.Mockito.verify(smsProvider, org.mockito.Mockito.atLeastOnce()).sendOtp(org.mockito.ArgumentMatchers.eq(phone), captor.capture());
        String newOtp = captor.getValue();

        // Verify new OTP
        mockMvc.perform(post("/auth/phone/verify-otp").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("phoneNumber", phone, "otp", newOtp, "purpose", "PHONE_SIGNUP"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.verified").value(true));

        // Complete signup
        String registerBody = objectMapper.writeValueAsString(Map.of(
                "username", username, "password", "Password@123", "phoneNumber", phone, "fullName", "Flow C"));
        mockMvc.perform(post("/register").contentType(MediaType.APPLICATION_JSON).content(registerBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken", notNullValue()));
    }

    @Test
    void register_rejectsUnverifiedEmail_atApiLevel() throws Exception {
        String email = uniqueEmail();
        String registerBody = objectMapper.writeValueAsString(Map.of(
                "username", "itestUnverified" + System.nanoTime(), "password", "Password@123", "email", email, "fullName", "Nope"));

        mockMvc.perform(post("/register").contentType(MediaType.APPLICATION_JSON).content(registerBody))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errorCode").value("VERIFICATION_REQUIRED"));
    }

    @Test
    void login_rejectsUnverifiedPhone_atApiLevel() throws Exception {
        doNothing().when(socialServiceClient).createUserProfile(any());
        String phone = uniquePhone();
        String username = "itestUnverifiedPhone" + System.nanoTime();

        String phoneOtp = capturePhoneOtp(phone, "PHONE_SIGNUP", false, null);
        mockMvc.perform(post("/auth/phone/verify-otp").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("phoneNumber", phone, "otp", phoneOtp, "purpose", "PHONE_SIGNUP"))))
                .andExpect(status().isOk());

        String registerBody = objectMapper.writeValueAsString(Map.of(
                "username", username, "password", "Password@123", "phoneNumber", phone, "fullName", "Unverified"));
        mockMvc.perform(post("/register").contentType(MediaType.APPLICATION_JSON).content(registerBody))
                .andExpect(status().isOk());

        // Simulate an edge-case row (e.g. a future data-migration bug) where
        // phone_verified ends up false despite the number being set —
        // login must still reject it, not just "phone never verified at all".
        var user = userRepository.findByPhoneNumber(phone).orElseThrow();
        user.setPhoneVerified(false);
        userRepository.save(user);

        mockMvc.perform(post("/login").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("identifier", phone, "password", "Password@123"))))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.errorCode").value("PHONE_NOT_VERIFIED"));
    }

    @Test
    void deviceSession_registeredOnLogin_listedThenRevoked_thenTokenStopsWorking() throws Exception {
        doNothing().when(socialServiceClient).createUserProfile(any());
        String email = uniqueEmail();
        String username = "itestDevice" + System.nanoTime();

        String emailOtp = captureEmailOtp(email);
        mockMvc.perform(post("/verify-otp").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("email", email, "otp", emailOtp))))
                .andExpect(status().isOk());

        String deviceInfo = "\"deviceInfo\":{\"deviceId\":\"itest-device-" + UUID.randomUUID()
                + "\",\"platform\":\"ANDROID\",\"osName\":\"Android\",\"osVersion\":\"14\",\"appVersion\":\"1.0.0\",\"deviceModel\":\"Pixel 8\"}";
        String registerBody = "{\"username\":\"" + username + "\",\"password\":\"Password@123\",\"email\":\""
                + email + "\",\"fullName\":\"Device Test\"," + deviceInfo + "}";
        String registerResponse = mockMvc.perform(post("/register").contentType(MediaType.APPLICATION_JSON).content(registerBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken", notNullValue()))
                .andReturn().getResponse().getContentAsString();
        Map<String, Object> tokens = objectMapper.readValue(registerResponse, Map.class);
        String accessToken = (String) tokens.get("accessToken");

        // The registered device shows up, is marked as this device, and has an ACTIVE session.
        String devicesResponse = mockMvc.perform(get("/devices").header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].platform").value("ANDROID"))
                .andExpect(jsonPath("$[0].sessionStatus").value("ACTIVE"))
                // Jackson serializes a boolean getter isCurrentDevice() as
                // JSON key "currentDevice" (strips the "is" prefix) — the
                // Flutter model must match this, not the Java field name.
                .andExpect(jsonPath("$[0].currentDevice").value(true))
                .andReturn().getResponse().getContentAsString();
        java.util.List<Map<String, Object>> devices = objectMapper.readValue(devicesResponse, java.util.List.class);
        Number deviceId = (Number) devices.get(0).get("deviceId");

        // Revoking it makes the SAME still-unexpired access token stop working on its very next request.
        mockMvc.perform(post("/devices/" + deviceId + "/revoke").header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk());

        mockMvc.perform(get("/devices").header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isForbidden());
    }
}
