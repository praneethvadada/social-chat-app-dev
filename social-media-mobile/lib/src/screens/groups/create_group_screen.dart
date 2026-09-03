import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../models/group.dart';
import '../../responsive/desktop_content_wrapper.dart';
import '../../services/api_service.dart';
import '../../services/group_api.dart';
import 'group_chat_screen.dart';

/// G1: create a group - name + member selection (search-based, like New Chat).
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _results = [];
  final Map<int, Map<String, dynamic>> _selected = {}; // userId -> user json
  bool _searching = false;
  bool _creating = false;
  int _myId = 0;

  @override
  void initState() {
    super.initState();
    ApiService.getUserId().then((id) => _myId = id ?? 0);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final users = await ApiService.searchUsers(query);
        if (!mounted) return;
        setState(() {
          _results = users
              .where((u) => (u['userId'] as int? ?? 0) != _myId)
              .toList();
          _searching = false;
        });
      } catch (e) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter a group name');
      return;
    }
    if (_selected.isEmpty) {
      Fluttertoast.showToast(msg: 'Select at least one member');
      return;
    }

    setState(() => _creating = true);
    try {
      final GroupSummary group = await GroupApi.createGroup(
        name: name,
        memberIds: _selected.keys.toList(),
      );

      if (group.skippedMemberIds.isNotEmpty) {
        // Neutral by design: never reveal WHY someone couldn't be added.
        Fluttertoast.showToast(msg: 'Some contacts couldn\'t be added');
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to create group');
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton(
              onPressed: _creating ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
              ),
              child: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create'),
            ),
          ),
        ],
      ),
      body: DesktopContentWrapper(
        maxWidth: 640,
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _nameController,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Group name',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _selected.values.map((u) {
                  final uid = u['userId'] as int? ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Chip(
                      label: Text(u['username']?.toString() ?? 'user'),
                      onDeleted: () => setState(() => _selected.remove(uid)),
                    ),
                  );
                }).toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search people to add...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final u = _results[i];
                final uid = u['userId'] as int? ?? 0;
                final selected = _selected.containsKey(uid);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (_) => setState(() {
                    if (selected) {
                      _selected.remove(uid);
                    } else {
                      _selected[uid] = u;
                    }
                  }),
                  secondary: CircleAvatar(
                    backgroundColor: primary,
                    child: Text(
                      (u['username']?.toString() ?? '?')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(u['fullName']?.toString() ??
                      u['username']?.toString() ??
                      'User'),
                  subtitle: Text('@${u['username'] ?? ''}'),
                );
              },
            ),
          ),
        ],
      ),
      ),
    );
  }
}
