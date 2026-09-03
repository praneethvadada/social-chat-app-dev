import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/post_service.dart';
import '../../state/app_state_manager.dart';
import 'blocked_users_screen.dart';
import '../forgot_password/forgot_password_otp_screen.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class PrivacySettingsScreen extends ConsumerStatefulWidget {
  /// True when shown as the detail pane of the desktop Settings
  /// index+detail split instead of pushed as its own route — hides the
  /// back arrow (nothing to pop) and, in `_deleteAccount`, skips the
  /// self-pop that closes "this screen" (there's no pushed route to close;
  /// `appNotifier.closeModal()` right after already handles leaving the
  /// settings panel either way).
  final bool embedded;
  const PrivacySettingsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen> {
  bool isPrivate = false;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final profile = await ApiService.getMyProfile();
      _currentUserId = profile['userId'] as int? ?? profile['id'] as int?;
    } catch (e) {
      print('Error loading current user ID: $e');
    }
  }

  Future<void> _loadSettings() async {
    await _loadCurrentUserId();
    if (_currentUserId == null) return;

    try {
      // Fetch actual privacy settings from backend (source of truth)
      final profile = await ApiService.getMyProfile();
      final backendIsPrivate = profile['isPrivate'] as bool? ?? false;
      
      setState(() {
        isPrivate = backendIsPrivate;
      });
      
      // Update local cache to match backend
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isPrivate_$_currentUserId', backendIsPrivate);
    } catch (e) {
      print('Error loading privacy settings: $e');
      // Fallback to local storage if backend fails
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        isPrivate = prefs.getBool('isPrivate_$_currentUserId') ?? false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_currentUserId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isPrivate_$_currentUserId', isPrivate);
  }


  Future<void> _onPrivateChanged(bool value) async {
    if (value && !isPrivate) {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Switch to Private Account?'),
          content: const Text(
            'When you make your account private, only people you approve can see your posts and followers. Existing followers won\'t be affected.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Yes, Make Private'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    // Update backend with the new privacy setting
    try {
      await ApiService.updateMyProfile(isPrivate: value);
      setState(() => isPrivate = value);
      await _saveSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Account is now private' : 'Account is now public'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating privacy settings: $e'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleChangePassword() async {
    // Navigate to forgot password flow
    final email = await _getUserEmail();
    if (email == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to retrieve email')),
        );
      }
      return;
    }

    try {
      await ApiService.requestPasswordReset(email);
      if (mounted) {
        // Show dialog saying OTP is sent
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('OTP Sent'),
            content: Text('An OTP has been sent to $email'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  // Navigate to OTP verification screen
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ForgotPasswordOtpScreen(email: email),
                    ),
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<String?> _getUserEmail() async {
    try {
      final profile = await ApiService.getMyProfile();
      return profile['email'] as String?;
    } catch (e) {
      print('Error getting user email: $e');
      return null;
    }
  }

  Future<void> _handleDeleteAccount() async {
    // First show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone. All your posts, messages, and data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show password confirmation dialog
    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please enter your password to confirm account deletion:'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(passwordController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );

    if (password == null || password.isEmpty) return;

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      await ApiService.deleteAccount(password);
      
      if (mounted) {
        // Get app state notifier
        final appNotifier = ref.read(appStateProvider.notifier);
        
        // Close loading dialog and this screen
        Navigator.of(context).pop(); // Close loading
        if (!widget.embedded) {
          Navigator.of(context).pop(); // Close privacy settings screen
        }
        
        // Clear app state providers
        ref.read(postProvider.notifier).clearPosts();
        
        // Small delay to let screens pop
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Close modal and navigate to welcome screen
        appNotifier.closeModal();
        appNotifier.goToGetStarted();
      }
    } catch (e) {
      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !widget.embedded, title: const Text('Privacy Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Private Account'),
            subtitle: const Text('Only approved followers can see your posts'),
            value: isPrivate,
            onChanged: _onPrivateChanged,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Change Password'),
            subtitle: const Text('Reset your account password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _handleChangePassword,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Close Friends'),
            subtitle: const Text('Manage your close friends list'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CloseFriendsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Blocked Users'),
            subtitle: const Text('Manage your blocked users'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const BlockedUsersScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton(
              onPressed: _handleDeleteAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Delete Account',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class CloseFriendsScreen extends StatelessWidget {
  const CloseFriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CloseFriendsManager();
  }
}

class _CloseFriendsManager extends StatefulWidget {
  const _CloseFriendsManager();

  @override
  State<_CloseFriendsManager> createState() => _CloseFriendsManagerState();
}

class _CloseFriendsManagerState extends State<_CloseFriendsManager> {
  List<Map<String, dynamic>> _closeFriends = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  bool _searching = false;
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _loadCloseFriends();
  }

  Future<void> _loadCloseFriends() async {
    setState(() => _loading = true);
    try {
      final friends = await ApiService.getCloseFriends();
      setState(() {
        _closeFriends = friends;
        _loading = false;
      });
    } catch (e) {
      print('Error loading close friends: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load close friends: $e')),
        );
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() => _searching = true);
    try {
      final results = await ApiService.searchUsers(query);
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (e) {
      print('Error searching users: $e');
      setState(() => _searching = false);
    }
  }

  Future<void> _addFriend(int userId, String fullName) async {
    try {
      await ApiService.addCloseFriend(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $fullName to close friends')),
        );
      }
      _searchController.clear();
      setState(() => _searchResults = []);
      await _loadCloseFriends();
    } catch (e) {
      print('Error adding close friend: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add close friend: $e')),
        );
      }
    }
  }

  Future<void> _removeFriend(int userId, String fullName) async {
    try {
      await ApiService.removeCloseFriend(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed $fullName from close friends')),
        );
      }
      await _loadCloseFriends();
    } catch (e) {
      print('Error removing close friend: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove close friend: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Close Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search users to add',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      _searchUsers(value);
                    },
                  ),
                ),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                if (_searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, i) {
                        final user = _searchResults[i];
                        final userId = user['id'] as int? ?? user['userId'] as int?;
                        final fullName = user['fullName'] as String? ?? 'Unknown';
                        final username = user['username'] as String? ?? '';
                        final profilePictureUrl = user['profilePictureUrl'] as String?;
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: profilePictureUrl != null
                                ? NetworkImage(profilePictureUrl)
                                : null,
                            child: profilePictureUrl == null
                                ? Text(fullName[0])
                                : null,
                          ),
                          title: Text(fullName),
                          subtitle: Text('@$username'),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle, color: AppColors.primary),
                            onPressed: () => _addFriend(userId!, fullName),
                          ),
                        );
                      },
                    ),
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.people, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${_closeFriends.length} Close Friends',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _closeFriends.isEmpty
                      ? const Center(
                          child: Text('No close friends yet.\nSearch and add users above.'))
                      : ListView.builder(
                          itemCount: _closeFriends.length,
                          itemBuilder: (context, i) {
                            final friend = _closeFriends[i];
                            final userId = friend['id'] as int? ?? friend['userId'] as int?;
                            final fullName = friend['fullName'] as String? ?? 'Unknown';
                            final username = friend['username'] as String? ?? '';
                            final profilePictureUrl = friend['profilePictureUrl'] as String?;
                            
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: profilePictureUrl != null
                                    ? NetworkImage(profilePictureUrl)
                                    : null,
                                child: profilePictureUrl == null
                                    ? Text(fullName[0])
                                    : null,
                              ),
                              title: Text(fullName),
                              subtitle: Text('@$username'),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle, color: AppColors.danger),
                                onPressed: () => _removeFriend(userId!, fullName),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
