import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/group.dart';
import '../../services/api_service.dart';
import '../../services/group_api.dart';
import '../../responsive/desktop_content_wrapper.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// G2: group info - profile, members grouped by role, and role/member actions
/// gated by the viewer's own role. The backend enforces every rule again; this
/// screen only avoids offering actions that would fail.
class GroupInfoScreen extends StatefulWidget {
  final GroupSummary group;

  const GroupInfoScreen({super.key, required this.group});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  /// Deep-link prefix shown with the invite code (host app resolves it).
  static const _inviteBase = 'https://socialchat.app/group/';

  List<GroupMember> _members = [];
  /// G3: active group bans (admins only; empty for regular members).
  List<GroupMember> _bans = [];
  bool _loading = true;
  int _myId = 0;
  String _myRole = 'MEMBER';
  late String _groupName;
  String? _description;

  /// True if the viewer left/was removed - the caller should pop the chat too.
  bool _membershipEnded = false;

  /// G5: live settings snapshot (starts from what the caller passed in).
  late GroupSummary _group;
  int _pendingRequests = 0;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _groupName = widget.group.name;
    _description = widget.group.description;
    _load();
  }

  Future<void> _load() async {
    _myId = await ApiService.getUserId() ?? 0;
    try {
      final members = await GroupApi.fetchMembers(widget.group.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _myRole = members
            .firstWhere((m) => m.userId == _myId,
                orElse: () => GroupMember(
                    userId: _myId, username: '', role: 'MEMBER'))
            .role;
        _loading = false;
      });

      // G5: refresh settings + pending join-request count (admins only).
      try {
        final groups = await GroupApi.fetchMyGroups();
        final fresh = groups.where((g) => g.id == widget.group.id);
        if (fresh.isNotEmpty && mounted) setState(() => _group = fresh.first);
      } catch (_) {}
      if (_iAmAdmin) {
        try {
          final reqs = await GroupApi.fetchJoinRequests(widget.group.id);
          if (mounted) setState(() => _pendingRequests = reqs.length);
        } catch (_) {}
      }

      // Ban list is admin-only; a 403 for regular members is expected.
      if (_iAmAdmin) {
        try {
          final bans = await GroupApi.fetchBans(widget.group.id);
          if (mounted) setState(() => _bans = bans);
        } catch (_) {
          if (mounted) setState(() => _bans = []);
        }
      } else if (mounted) {
        setState(() => _bans = []);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _iAmOwner => _myRole == 'OWNER';
  bool get _iAmAdmin => _myRole == 'OWNER' || _myRole == 'ADMIN';

  Future<void> _run(Future<void> Function() action, String successMsg) async {
    try {
      await action();
      Fluttertoast.showToast(msg: successMsg);
      await _load();
    } catch (e) {
      // Surface the backend's own permission wording.
      Fluttertoast.showToast(
          msg: e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _memberActions(GroupMember member) {
    if (member.userId == _myId) return; // no actions on yourself here

    final actions = <Widget>[];

    if (_iAmOwner && !member.isOwner) {
      actions.add(ListTile(
        leading: Icon(member.isAdmin
            ? Icons.remove_moderator
            : Icons.admin_panel_settings),
        title: Text(member.isAdmin ? 'Dismiss as admin' : 'Make admin'),
        onTap: () {
          Navigator.pop(context);
          _run(
              () => GroupApi.changeRole(widget.group.id, member.userId,
                  member.isAdmin ? 'MEMBER' : 'ADMIN'),
              member.isAdmin ? 'Admin dismissed' : 'Now an admin');
        },
      ));
      actions.add(ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: const Text('Transfer ownership'),
        onTap: () async {
          Navigator.pop(context);
          final ok = await _confirm('Transfer ownership?',
              'You will become an admin and ${member.displayName} becomes the owner.');
          if (ok) {
            await _run(
                () => GroupApi.transferOwnership(widget.group.id, member.userId),
                'Ownership transferred');
          }
        },
      ));
    }

    // Admins can remove members; the backend still blocks admin-on-admin.
    if (_iAmAdmin && !member.isOwner) {
      actions.add(ListTile(
        leading: const Icon(Icons.person_remove, color: AppColors.gold),
        title: const Text('Remove from group'),
        subtitle: const Text('They can be added back later',
            style: TextStyle(fontSize: 11)),
        onTap: () {
          Navigator.pop(context);
          _run(() => GroupApi.removeMember(widget.group.id, member.userId),
              '${member.displayName} removed');
        },
      ));
      // G3: ban is a DIFFERENT, stronger action than remove (spec §15).
      actions.add(ListTile(
        leading: const Icon(Icons.gavel, color: AppColors.danger),
        title: const Text('Ban from group',
            style: TextStyle(color: AppColors.danger)),
        subtitle: const Text('Removes them and blocks rejoining',
            style: TextStyle(fontSize: 11)),
        onTap: () async {
          Navigator.pop(context);
          final ok = await _confirm('Ban ${member.displayName}?',
              'They will be removed from this group and cannot rejoin until the ban is lifted.\n\n'
              'This affects this group only - it is not a personal block.');
          if (ok) {
            await _run(() => GroupApi.banMember(widget.group.id, member.userId),
                '${member.displayName} banned');
          }
        },
      ));
    }

    if (actions.isEmpty) return;

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(member.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _leave() async {
    // Spec §V: the owner must hand over the group before leaving.
    if (_iAmOwner && _members.length > 1) {
      Fluttertoast.showToast(
          msg: 'Transfer ownership before leaving');
      return;
    }
    final ok = await _confirm(
        'Leave group?', 'You will no longer receive messages from this group.');
    if (!ok) return;
    try {
      await GroupApi.leaveGroup(widget.group.id);
      _membershipEnded = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      Fluttertoast.showToast(
          msg: e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Search-and-select sheet for adding members. Existing members are excluded;
  /// anyone the backend refuses comes back only as a neutral count.
  Future<void> _addMembers() async {
    final searchController = TextEditingController();
    final selected = <int>{};
    List<Map<String, dynamic>> results = [];
    Timer? debounce;

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search people to add...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (query) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 400),
                          () async {
                        if (query.trim().isEmpty) {
                          setSheetState(() => results = []);
                          return;
                        }
                        try {
                          final users =
                              await ApiService.searchUsers(query.trim());
                          final existing =
                              _members.map((m) => m.userId).toSet();
                          setSheetState(() => results = users
                              .where((u) =>
                                  !existing.contains(u['userId'] as int? ?? 0))
                              .toList());
                        } catch (_) {}
                      });
                    },
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final u = results[i];
                      final uid = u['userId'] as int? ?? 0;
                      return CheckboxListTile(
                        value: selected.contains(uid),
                        onChanged: (_) => setSheetState(() {
                          selected.contains(uid)
                              ? selected.remove(uid)
                              : selected.add(uid);
                        }),
                        title: Text(u['fullName']?.toString() ??
                            u['username']?.toString() ??
                            'User'),
                        subtitle: Text('@${u['username'] ?? ''}'),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(sheetContext, true),
                        child: Text('Add ${selected.length} member(s)'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    debounce?.cancel();
    if (added != true || selected.isEmpty) return;

    await _run(() async {
      final skipped =
          await GroupApi.addMembers(widget.group.id, selected.toList());
      if (skipped.isNotEmpty && mounted) {
        // Neutral by design - never say why (§25).
        Fluttertoast.showToast(msg: 'Some contacts couldn\'t be added');
      }
    }, 'Members added');
  }


  // ---------------- G5: permissions / invite / requests / notifications ----------------

  /// Spec §R: settings are stored per group and enforced by the backend; this
  /// screen only edits them.
  Future<void> _openPermissions() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          Widget row(String title, String current, String field) {
            return ListTile(
              title: Text(title),
              trailing: DropdownButton<String>(
                value: current,
                items: const [
                  DropdownMenuItem(value: 'EVERYONE', child: Text('Everyone')),
                  DropdownMenuItem(value: 'ADMINS', child: Text('Admins only')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  try {
                    final updated = await GroupApi.updatePermissions(
                      widget.group.id,
                      whoCanSend: field == 'send' ? v : null,
                      whoCanEditInfo: field == 'edit' ? v : null,
                      whoCanAddMembers: field == 'add' ? v : null,
                      whoCanPin: field == 'pin' ? v : null,
                    );
                    setSheet(() {});
                    if (mounted) setState(() => _group = updated);
                  } catch (e) {
                    Fluttertoast.showToast(
                        msg: e.toString().replaceFirst('Exception: ', ''));
                  }
                },
              ),
            );
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Group Permissions',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                row('Who can send messages?', _group.whoCanSend, 'send'),
                row('Who can edit group info?', _group.whoCanEditInfo, 'edit'),
                row('Who can add members?', _group.whoCanAddMembers, 'add'),
                row('Who can pin messages?', _group.whoCanPin, 'pin'),
                SwitchListTile(
                  title: const Text('Approve new members'),
                  subtitle: const Text('Invite-link joins become requests'),
                  value: _group.approveNewMembers,
                  onChanged: (v) async {
                    try {
                      final updated = await GroupApi.updatePermissions(
                          widget.group.id, approveNewMembers: v);
                      setSheet(() {});
                      if (mounted) setState(() => _group = updated);
                    } catch (e) {
                      Fluttertoast.showToast(
                          msg: e.toString().replaceFirst('Exception: ', ''));
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
    _load();
  }

  /// Spec §O: shareable link, copyable and resettable.
  Future<void> _openInvite() async {
    String? code;
    try {
      code = await GroupApi.fetchInviteCode(widget.group.id);
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Invite to Group',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              // GAP-4 (spec §O): scannable QR for the invite link.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.white, // QR needs a light background to scan
                  child: QrImageView(
                    data: '$_inviteBase$code',
                    version: QrVersions.auto,
                    size: 170,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SelectableText('$_inviteBase$code',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy link'),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: '$_inviteBase$code'));
                  Fluttertoast.showToast(msg: 'Link copied');
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh, color: AppColors.danger),
                title: const Text('Reset link'),
                subtitle: const Text('The old link stops working immediately'),
                onTap: () async {
                  try {
                    final fresh =
                        await GroupApi.resetInviteCode(widget.group.id);
                    setSheet(() => code = fresh);
                    Fluttertoast.showToast(msg: 'New link generated');
                  } catch (e) {
                    Fluttertoast.showToast(
                        msg: e.toString().replaceFirst('Exception: ', ''));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Spec §P: admins accept or reject pending requests.
  Future<void> _openJoinRequests() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => FutureBuilder<List<GroupMember>>(
          future: GroupApi.fetchJoinRequests(widget.group.id),
          builder: (context, snap) {
            final requests = snap.data ?? [];
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Join Requests',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const Divider(height: 1),
                  if (snap.connectionState == ConnectionState.waiting)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator())
                  else if (requests.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No pending requests'))
                  else
                    ...requests.map((r) => ListTile(
                          leading: CircleAvatar(
                              child: Text(r.displayName
                                  .substring(0, 1)
                                  .toUpperCase())),
                          title: Text(r.displayName),
                          subtitle: Text('@${r.username}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  await GroupApi.decideJoinRequest(
                                      widget.group.id, r.userId, true);
                                  setSheet(() {});
                                  _load();
                                },
                                child: const Text('Accept'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await GroupApi.decideJoinRequest(
                                      widget.group.id, r.userId, false);
                                  setSheet(() {});
                                  _load();
                                },
                                child: const Text('Reject',
                                    style: TextStyle(color: AppColors.danger)),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            );
          },
        ),
      ),
    );
    _load();
  }

  /// Spec §U: my own notification preference for this group.
  Future<void> _openNotifications() async {
    await showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Group Notifications',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            for (final entry in const {
              'ALL': 'All messages',
              'MENTIONS': 'Mentions only',
              'NONE': 'Muted',
            }.entries)
              RadioListTile<String>(
                value: entry.key,
                groupValue: _group.myNotificationLevel,
                title: Text(entry.value),
                onChanged: (v) async {
                  Navigator.pop(sheet);
                  try {
                    await GroupApi.setNotifications(widget.group.id, level: v);
                    Fluttertoast.showToast(msg: 'Notification setting saved');
                    _load();
                  } catch (e) {
                    Fluttertoast.showToast(
                        msg: e.toString().replaceFirst('Exception: ', ''));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editInfo() async {
    final nameController = TextEditingController(text: _groupName);
    final descController = TextEditingController(text: _description ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit group info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              maxLength: 100,
              decoration: const InputDecoration(
                  labelText: 'Group name', counterText: ''),
            ),
            TextField(
              controller: descController,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Description', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;
    await _run(() async {
      final updated = await GroupApi.updateInfo(widget.group.id,
          name: nameController.text.trim(),
          description: descController.text.trim());
      if (mounted) {
        setState(() {
          _groupName = updated.name;
          _description = updated.description;
        });
      }
    }, 'Group updated');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final owners = _members.where((m) => m.isOwner).toList();
    final admins = _members.where((m) => m.isAdmin).toList();
    final regular =
        _members.where((m) => !m.isOwner && !m.isAdmin).toList();

    return PopScope(
      canPop: true,
      onPopInvoked: (_) {},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Group Info'),
          actions: [
            if (_iAmAdmin)
              IconButton(
                tooltip: 'Edit info',
                icon: const Icon(Icons.edit),
                onPressed: _editInfo,
              ),
          ],
        ),
        body: DesktopContentWrapper(
        maxWidth: 640,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: primary,
                      child: const Icon(Icons.groups,
                          color: Colors.white, size: 44),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(_groupName,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  Center(
                    child: Text('${_members.length} members',
                        style: TextStyle(color: theme.hintColor)),
                  ),
                  if (_description != null && _description!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(_description!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.hintColor)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(),
                  if (_iAmAdmin)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: primary.withOpacity(0.15),
                        child: Icon(Icons.person_add, color: primary),
                      ),
                      title: const Text('Add members'),
                      onTap: _addMembers,
                    ),
                  if (owners.isNotEmpty) _section('Owner', owners, primary),
                  if (admins.isNotEmpty) _section('Admins', admins, primary),
                  if (regular.isNotEmpty)
                    _section('Members', regular, primary),
                  // G3: banned users - admins only
                  if (_bans.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text('Banned (${_bans.length})',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger)),
                    ),
                    ..._bans.map((b) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.mutedSolid,
                            child: const Icon(Icons.gavel,
                                color: Colors.white, size: 18),
                          ),
                          title: Text(b.displayName),
                          subtitle: const Text('Cannot rejoin',
                              style: TextStyle(fontSize: 11)),
                          trailing: TextButton(
                            onPressed: () => _run(
                                () => GroupApi.unbanMember(
                                    widget.group.id, b.userId),
                                'Ban lifted'),
                            child: const Text('Unban'),
                          ),
                        )),
                  ],
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Notifications'),
                    subtitle: Text(_group.myNotificationLevel == 'ALL'
                        ? 'All messages'
                        : _group.myNotificationLevel == 'MENTIONS'
                            ? 'Mentions only'
                            : 'Muted'),
                    onTap: _openNotifications,
                  ),
                  if (_iAmAdmin) ...[
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: const Text('Invite to group'),
                      subtitle: const Text('Share or reset the invite link'),
                      onTap: _openInvite,
                    ),
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Group permissions'),
                      subtitle: const Text('Who can send, edit, add or pin'),
                      onTap: _openPermissions,
                    ),
                    ListTile(
                      leading: const Icon(Icons.how_to_reg),
                      title: const Text('Join requests'),
                      trailing: _pendingRequests > 0
                          ? CircleAvatar(
                              radius: 11,
                              backgroundColor: AppColors.danger,
                              child: Text('$_pendingRequests',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white)))
                          : null,
                      onTap: _openJoinRequests,
                    ),
                  ],
                  const Divider(),
                  ListTile(
                    leading:
                        const Icon(Icons.exit_to_app, color: AppColors.danger),
                    title: const Text('Leave group',
                        style: TextStyle(color: AppColors.danger)),
                    onTap: _leave,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
        ),
      ),
    );
  }

  Widget _section(String title, List<GroupMember> members, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).hintColor)),
        ),
        ...members.map((m) => ListTile(
              leading: CircleAvatar(
                backgroundColor: primary,
                backgroundImage: m.profilePictureUrl != null
                    ? NetworkImage(m.profilePictureUrl!)
                    : null,
                child: m.profilePictureUrl == null
                    ? Text(m.displayName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white))
                    : null,
              ),
              title: Row(
                children: [
                  Flexible(child: Text(m.displayName)),
                  if (m.userId == _myId)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('(You)',
                          style: TextStyle(fontSize: 11, color: AppColors.mutedSolid)),
                    ),
                ],
              ),
              subtitle: Text('@${m.username}'),
              trailing: m.isOwner
                  ? const Text('👑', style: TextStyle(fontSize: 16))
                  : m.isAdmin
                      ? const Text('🛡', style: TextStyle(fontSize: 16))
                      : null,
              onTap: () => _memberActions(m),
            )),
      ],
    );
  }
}
