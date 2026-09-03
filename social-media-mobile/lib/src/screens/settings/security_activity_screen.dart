import 'package:flutter/material.dart';
import 'package:social_chat_app/src/theme/colors.dart';
import '../../models/security_event.dart';
import '../../services/api_service.dart';

/// Settings → Security → "Security Activity" (spec Phase 8): a read-only
/// log of security-relevant events on this account — logins, new devices,
/// password/2FA changes, remote logouts, etc. See SecurityEvent.label for
/// the full list of what can appear here.
class SecurityActivityScreen extends StatefulWidget {
  const SecurityActivityScreen({super.key});

  @override
  State<SecurityActivityScreen> createState() => _SecurityActivityScreenState();
}

class _SecurityActivityScreenState extends State<SecurityActivityScreen> {
  static const int _pageSize = 20;

  final List<SecurityEvent> _events = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await ApiService.getSecurityEvents(page: 0, size: _pageSize);
      setState(() {
        _events
          ..clear()
          ..addAll(events);
        _page = 0;
        _hasMore = events.length == _pageSize;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final events = await ApiService.getSecurityEvents(page: nextPage, size: _pageSize);
      setState(() {
        _events.addAll(events);
        _page = nextPage;
        _hasMore = events.length == _pageSize;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load more: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  IconData _iconFor(String eventType) {
    switch (eventType) {
      case 'LOGIN':
        return Icons.login;
      case 'LOGOUT':
        return Icons.logout;
      case 'NEW_DEVICE':
        return Icons.devices_other;
      case 'PASSWORD_CHANGED':
        return Icons.password;
      case 'EMAIL_CHANGED':
        return Icons.email_outlined;
      case 'PHONE_CHANGED':
        return Icons.phone_android;
      case 'TWO_FA_ENABLED':
      case 'TWO_FA_DISABLED':
      case 'TWO_FA_METHOD_CHANGED':
        return Icons.shield_outlined;
      case 'SESSION_REVOKED':
      case 'WEB_SESSION_REPLACED':
        return Icons.block;
      case 'LOCAL_STORAGE_DEVICE_CHANGED':
        return Icons.storage;
      case 'ACCOUNT_DELETED':
        return Icons.delete_forever;
      default:
        return Icons.info_outline;
    }
  }

  Color _colorFor(String eventType) {
    switch (eventType) {
      case 'ACCOUNT_DELETED':
      case 'SESSION_REVOKED':
      case 'WEB_SESSION_REPLACED':
        return AppColors.danger;
      case 'TWO_FA_ENABLED':
        return AppColors.success;
      case 'TWO_FA_DISABLED':
        return AppColors.danger;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security Activity')),
      body: RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text('Failed to load activity: $_error')),
                    ],
                  )
                : _events.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 80),
                          Center(child: Text('No security activity yet')),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _events.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index >= _events.length) {
                            // Defer to after this frame — calling setState
                            // (inside _loadMore, once the fetch resolves)
                            // directly from itemBuilder would run during the
                            // build phase and throw.
                            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          }
                          final event = _events[index];
                          return _EventTile(
                            event: event,
                            icon: _iconFor(event.eventType),
                            color: _colorFor(event.eventType),
                          );
                        },
                      ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final SecurityEvent event;
  final IconData icon;
  final Color color;

  const _EventTile({required this.event, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (event.deviceDisplayName != null) subtitleParts.add(event.deviceDisplayName!);
    if (event.timeAgo.isNotEmpty) subtitleParts.add(event.timeAgo);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitleParts.join(' · '), style: TextStyle(color: AppColors.mutedSolid, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
