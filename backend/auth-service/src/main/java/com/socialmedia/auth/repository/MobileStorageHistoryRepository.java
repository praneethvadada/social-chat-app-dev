package com.socialmedia.auth.repository;

import com.socialmedia.auth.entity.MobileStorageHistory;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface MobileStorageHistoryRepository extends JpaRepository<MobileStorageHistory, Long> {
}
