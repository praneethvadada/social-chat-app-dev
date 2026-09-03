package com.socialmedia.auth.repository;

import com.socialmedia.auth.entity.Device;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface DeviceRepository extends JpaRepository<Device, Long> {

    Optional<Device> findByUserIdAndDeviceId(Long userId, String deviceId);

    List<Device> findByUserId(Long userId);
}
