package com.socialmedia.auth.repository;

import com.socialmedia.auth.entity.UserSession;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserSessionRepository extends JpaRepository<UserSession, Long> {

    Optional<UserSession> findBySessionToken(String sessionToken);

    Optional<UserSession> findByDeviceIdAndStatus(Long deviceId, String status);

    List<UserSession> findByUserIdAndStatus(Long userId, String status);

    List<UserSession> findByUserId(Long userId);
}
