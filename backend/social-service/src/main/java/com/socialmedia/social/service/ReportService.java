package com.socialmedia.social.service;

import com.socialmedia.social.dto.ReportRequest;
import com.socialmedia.social.dto.ReportResponse;
import com.socialmedia.social.entity.Report;
import com.socialmedia.social.repository.CommentRepository;
import com.socialmedia.social.repository.PostRepository;
import com.socialmedia.social.repository.ReportRepository;
import com.socialmedia.social.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Locale;
import java.util.NoSuchElementException;

@Service
@RequiredArgsConstructor
@Slf4j
public class ReportService {

    private final ReportRepository reportRepository;
    private final PostRepository postRepository;
    private final CommentRepository commentRepository;
    private final UserProfileRepository userProfileRepository;

    /**
     * Files a report. Reporting the same target twice is not an error: the
     * existing report is returned with alreadyReported=true, so a retry or a
     * double tap never shows the user a failure.
     */
    @Transactional
    public ReportResponse createReport(Long reporterId, ReportRequest request) {
        Report.TargetType targetType = parseEnum(Report.TargetType.class, request.getTargetType(), "targetType");
        Report.Reason reason = parseEnum(Report.Reason.class, request.getReason(), "reason");
        Long targetId = request.getTargetId();

        Long reportedUserId = resolveReportedUser(targetType, targetId);
        if (reportedUserId.equals(reporterId)) {
            throw new IllegalArgumentException("You can't report yourself or your own content");
        }

        var existing = reportRepository.findByReporterIdAndTargetTypeAndTargetId(reporterId, targetType, targetId);
        if (existing.isPresent()) {
            return toResponse(existing.get(), true);
        }

        Report report = new Report();
        report.setReporterId(reporterId);
        report.setTargetType(targetType);
        report.setTargetId(targetId);
        report.setReportedUserId(reportedUserId);
        report.setReason(reason);
        String details = request.getDetails();
        report.setDetails(details == null || details.isBlank() ? null : details.trim());

        try {
            Report saved = reportRepository.saveAndFlush(report);
            log.info("Report {} filed: {} {} (user {}) for {} by user {}",
                    saved.getId(), targetType, targetId, reportedUserId, reason, reporterId);
            return toResponse(saved, false);
        } catch (DataIntegrityViolationException e) {
            // Concurrent duplicate (double tap): the unique key caught it.
            return reportRepository.findByReporterIdAndTargetTypeAndTargetId(reporterId, targetType, targetId)
                    .map(r -> toResponse(r, true))
                    .orElseThrow(() -> e);
        }
    }

    private Long resolveReportedUser(Report.TargetType targetType, Long targetId) {
        return switch (targetType) {
            case USER -> {
                if (!userProfileRepository.existsByUserId(targetId)) {
                    throw new NoSuchElementException("User not found");
                }
                yield targetId;
            }
            case POST -> postRepository.findById(targetId)
                    .orElseThrow(() -> new NoSuchElementException("Post not found"))
                    .getUserId();
            case COMMENT -> commentRepository.findById(targetId)
                    .orElseThrow(() -> new NoSuchElementException("Comment not found"))
                    .getUserId();
        };
    }

    private static <E extends Enum<E>> E parseEnum(Class<E> type, String value, String field) {
        try {
            return Enum.valueOf(type, value.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new IllegalArgumentException("Invalid " + field + ": " + value);
        }
    }

    private static ReportResponse toResponse(Report report, boolean alreadyReported) {
        return new ReportResponse(report.getId(), report.getStatus().name(), alreadyReported);
    }
}
