import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';
import '../../utils/friendly_error.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final users = await ApiService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = FriendlyError.messageOf(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unblockUser(int userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock User'),
        content: Text('Are you sure you want to unblock @$username?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.unblockUser(userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('@$username has been unblocked')),
          );
          // Reload the list
          await _loadBlockedUsers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to unblock user: ${e.toString()}')),
          );
        }
      }
    }
  }

  String _getInitials(String? username, int userId) {
    if (username != null && username.isNotEmpty) {
      // Remove @ if present
      final cleanUsername = username.startsWith('@') ? username.substring(1) : username;
      if (cleanUsername.isNotEmpty) {
        return cleanUsername[0].toUpperCase();
      }
    }
    return 'U';  // Default fallback
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Blocked Users',
          style: TextStyle(
            color: primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadBlockedUsers,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: AppColors.mutedSolid),
                        const SizedBox(height: 16),
                        Text(_errorMessage!, style: TextStyle(color: AppColors.mutedSolid)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadBlockedUsers,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _blockedUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.block, size: 64, color: AppColors.mutedSolid),
                            const SizedBox(height: 16),
                            Text(
                              'No blocked users',
                              style: TextStyle(
                                color: AppColors.mutedSolid,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Users you block will appear here',
                              style: TextStyle(
                                color: AppColors.mutedSolid,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _blockedUsers.length,
                        itemBuilder: (context, index) {
                          final user = _blockedUsers[index];
                          final userId = user['blockedUserId'] as int;
                          final username = user['blockedUsername']?.toString() ?? 'User$userId';
                          final profilePicUrl = user['blockedProfilePicUrl']?.toString();
                          final blockedAt = user['blockedAt']?.toString();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: primary,
                                backgroundImage: profilePicUrl != null && profilePicUrl.isNotEmpty
                                    ? NetworkImage(profilePicUrl)
                                    : null,
                                child: profilePicUrl == null || profilePicUrl.isEmpty
                                    ? Text(
                                        _getInitials(username, userId),
                                        style: const TextStyle(color: Colors.white),
                                      )
                                    : null,
                              ),
                              title: Text(
                                '@$username',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: blockedAt != null
                                  ? Text(
                                      'Blocked ${_formatDate(blockedAt)}',
                                      style: TextStyle(
                                        color: AppColors.mutedSolid,
                                        fontSize: 12,
                                      ),
                                    )
                                  : null,
                              trailing: OutlinedButton(
                                onPressed: () => _unblockUser(userId, username),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(color: AppColors.primary),
                                ),
                                child: const Text('Unblock'),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return 'today';
      } else if (diff.inDays == 1) {
        return 'yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else if (diff.inDays < 30) {
        return '${(diff.inDays / 7).floor()} weeks ago';
      } else {
        return '${(diff.inDays / 30).floor()} months ago';
      }
    } catch (e) {
      return '';
    }
  }
}
