import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/colors.dart';

/// What a report is about. Names match the backend's Report.TargetType.
enum ReportTarget { user, post, comment }

/// Backend Report.Reason names with the wording shown to the user.
const List<(String, String)> _reasons = [
  ('SPAM', 'Spam'),
  ('HARASSMENT', 'Harassment or bullying'),
  ('HATE_SPEECH', 'Hate speech or symbols'),
  ('NUDITY', 'Nudity or sexual content'),
  ('VIOLENCE', 'Violence or dangerous acts'),
  ('SCAM', 'Scam or fraud'),
  ('IMPERSONATION', 'Pretending to be someone else'),
  ('OTHER', 'Something else'),
];

/// Shows the report flow for a user, post or comment (Play Store UGC policy
/// requires in-app reporting of users and content).
///
/// When [blockUserId] is given the sheet also offers to block that user.
/// Returns true if the user was blocked, so callers can leave screens that
/// no longer make sense (e.g. the blocked user's profile).
Future<bool> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required int targetId,
  int? blockUserId,
  String? blockUserName,
}) async {
  final blocked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      target: target,
      targetId: targetId,
      blockUserId: blockUserId,
      blockUserName: blockUserName,
    ),
  );
  return blocked ?? false;
}

class _ReportSheet extends StatefulWidget {
  final ReportTarget target;
  final int targetId;
  final int? blockUserId;
  final String? blockUserName;

  const _ReportSheet({
    required this.target,
    required this.targetId,
    this.blockUserId,
    this.blockUserName,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _detailsController = TextEditingController();
  String? _reason;
  bool _alsoBlock = false;
  bool _sending = false;
  String? _error;

  String get _title => switch (widget.target) {
        ReportTarget.user => 'Report user',
        ReportTarget.post => 'Report post',
        ReportTarget.comment => 'Report comment',
      };

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await ApiService.reportContent(
        targetType: widget.target.name.toUpperCase(),
        targetId: widget.targetId,
        reason: reason,
        details: _detailsController.text,
      );
    } catch (e) {
      debugPrint('[Report] failed: $e');
      if (mounted) {
        setState(() {
          _sending = false;
          _error = "Couldn't send your report. Check your connection and try again.";
        });
      }
      return;
    }

    var blocked = false;
    final blockUserId = widget.blockUserId;
    if (_alsoBlock && blockUserId != null) {
      try {
        await ApiService.blockUser(blockUserId, reason: 'Reported: $reason');
        blocked = true;
      } catch (e) {
        // The report itself went through; blocking can be retried from the profile.
        debugPrint('[Report] block after report failed: $e');
      }
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(blocked);
    messenger.showSnackBar(SnackBar(
      content: Text(blocked
          ? "Thanks for reporting. We'll review it, and you've blocked this user."
          : "Thanks for reporting. We'll review it."),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blockName = widget.blockUserName;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    "Why are you reporting this? The person won't know who reported them.",
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final (code, label) in _reasons)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(label),
                      trailing: Icon(
                        _reason == code ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _reason == code ? AppColors.primary : theme.disabledColor,
                      ),
                      onTap: _sending ? null : () => setState(() => _reason = code),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _detailsController,
                    enabled: !_sending,
                    maxLength: 500,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Add details (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (widget.blockUserId != null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _alsoBlock,
                      onChanged: _sending ? null : (v) => setState(() => _alsoBlock = v ?? false),
                      title: Text(blockName != null && blockName.isNotEmpty
                          ? 'Also block $blockName'
                          : 'Also block this user'),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                      onPressed: _reason == null || _sending ? null : _submit,
                      child: _sending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Submit report'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
