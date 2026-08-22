package com.socialmedia.chats.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Configuration;

import java.io.FileInputStream;
import java.io.IOException;

/**
 * Firebase Configuration for Cloud Messaging
 * Initializes Firebase Admin SDK for sending push notifications
 */
@Configuration
@Slf4j
public class FirebaseConfig {

    public FirebaseConfig() {
        try {
            // Try to load Firebase service account key
            String keyPath = System.getenv("FIREBASE_KEY_PATH");
            GoogleCredentials credentials = null;
            
            if (keyPath != null && !keyPath.isEmpty()) {
                try {
                    FileInputStream serviceAccount = new FileInputStream(keyPath);
                    credentials = GoogleCredentials.fromStream(serviceAccount);
                    log.info("[Firebase] 📂 Loaded serviceAccountKey from ENV path: {}", keyPath);
                } catch (IOException e) {
                    log.warn("[Firebase] ⚠️ Failed to load from ENV path: {}. Trying resources...", e.getMessage());
                }
            }
            
            if (credentials == null) {
                // Fallback: Try loading from classpath
                java.io.InputStream serviceAccount = getClass().getClassLoader().getResourceAsStream("serviceAccountKey.json");
                if (serviceAccount != null) {
                    credentials = GoogleCredentials.fromStream(serviceAccount);
                    log.info("[Firebase] 📂 Loaded serviceAccountKey.json from resources");
                }
            }

            if (credentials != null) {
                FirebaseOptions options = FirebaseOptions.builder()
                        .setCredentials(credentials)
                        .build();
                
                if (FirebaseApp.getApps().isEmpty()) {
                    FirebaseApp.initializeApp(options);
                    log.info("[Firebase] ✅ Firebase Admin SDK initialized successfully");
                } else {
                    log.info("[Firebase] ℹ️ Firebase Admin SDK already initialized");
                }
            } else {
                log.warn("[Firebase] ⚠️ FIREBASE_KEY_PATH not set and serviceAccountKey.json not found in resources.");
                log.warn("[Firebase] Push notifications will NOT work.");
            }
        } catch (IOException e) {
            log.error("[Firebase] ❌ Error initializing Firebase Admin SDK: {}", e.getMessage());
        }
    }
}
