package com.socialmedia.social.repository;

import com.socialmedia.social.entity.Report;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface ReportRepository extends JpaRepository<Report, Long> {

    Optional<Report> findByReporterIdAndTargetTypeAndTargetId(
            Long reporterId, Report.TargetType targetType, Long targetId);
}
