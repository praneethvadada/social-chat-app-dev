import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/avatar_initial.dart';
import '../../services/api_service.dart';
import '../user_profile_screen.dart';
import '../../responsive/desktop_content_wrapper.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getFollowRequests();
      setState(() {
        _requests = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _respond(int requestId, bool accept, int index) async {
    try {
      await ApiService.respondFollowRequest(requestId, accept);
      setState(() {
        _requests.removeAt(index);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? 'Follow accepted' : 'Request declined')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text('Follow Requests', style: TextStyle(color: primary, fontSize: 20, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: DesktopContentWrapper(
        maxWidth: 640,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Error: $_error'),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadRequests, child: const Text('Retry')),
                      ],
                    ),
                  )
                : _requests.isEmpty
                    ? const Center(child: Text('No follow requests'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 18),
                        itemBuilder: (context, i) {
                          final r = _requests[i];
                          final requester = r['requester'] as Map<String, dynamic>? ?? {};
                          final displayName = requester['fullName'] ?? requester['username'] ?? 'Unknown';
                          final handle = requester['username'] != null ? '@${requester['username']}' : '';
                          final initials = (requester['fullName'] ?? requester['username'] ?? 'U')
                              .toString()
                              .split(' ')
                              .map((s) => s.isNotEmpty ? s[0] : '')
                              .take(2)
                              .join()
                              .toUpperCase();

                          final requesterId = (requester['userId'] ?? requester['requesterId']) as int?;
                          final profilePic = requester['profilePictureUrl'] as String?;

                          return InkWell(
                            onTap: requesterId != null
                                ? () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UserProfileScreen(userId: requesterId),
                                      ),
                                    );
                                    // Refresh list after returning
                                    await _loadRequests();
                                  }
                                : null,
                            child: Row(
                              children: [
                                profilePic != null && profilePic.isNotEmpty
                                    ? CircleAvatar(
                                        radius: 22,
                                        backgroundImage: NetworkImage(
                                          profilePic,
                                        ),
                                      )
                                    : AvatarInitial(initials: initials, size: 44, showOnline: false),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(handle, style: TextStyle(color: AppColors.mutedSolid)),
                                      if (requester['mutualCount'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6.0),
                                          child: Text('${requester['mutualCount']} mutual connections', style: TextStyle(color: AppColors.mutedSolid, fontSize: 12)),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () async {
                                    final reqId = r['id'] as int?;
                                    if (reqId != null) await _respond(reqId, true, i);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                  ),
                                  child: const Text('Accept', style: TextStyle(color: Colors.white)),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () async {
                                    final reqId = r['id'] as int?;
                                    if (reqId != null) await _respond(reqId, false, i);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.danger,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  child: const Text('Decline', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
        ),
      ),
    );
  }
}
