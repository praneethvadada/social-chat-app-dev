package com.socialmedia.social.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.info.Contact;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.info.License;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.servers.Server;
import org.springframework.context.annotation.Configuration;

@Configuration
@OpenAPIDefinition(
    info = @Info(
        title = "Social Media Service API",
        version = "1.0.0",
        description = "Social Features API including Posts, Comments, Likes, Saves, Shares, and Real-time Chat",
        contact = @Contact(
            name = "API Support",
            email = "support@socialmedia.com"
        ),
        license = @License(
            name = "Apache 2.0",
            url = "https://www.apache.org/licenses/LICENSE-2.0"
        )
    ),
    servers = {
        @Server(
            url = "http://localhost:8082",
            description = "Local Development Server"
        ),
        @Server(
            url = "http://localhost:8080/api/social",
            description = "API Gateway"
        )
    }
)
@SecurityScheme(
    name = "Bearer Authentication",
    type = SecuritySchemeType.HTTP,
    bearerFormat = "JWT",
    scheme = "bearer",
    description = "JWT token from /api/auth/login or /api/auth/register"
)
public class OpenApiConfig {
}
