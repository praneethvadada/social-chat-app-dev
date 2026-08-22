import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/user_search.dart';


class TagPeopleDialog extends StatefulWidget {
  final List<UserSearch> initiallyTagged;
  const TagPeopleDialog({Key? key, this.initiallyTagged = const []}) : super(key: key);

  @override
  State<TagPeopleDialog> createState() => _TagPeopleDialogState();
}

class _TagPeopleDialogState extends State<TagPeopleDialog> {
  final TextEditingController _controller = TextEditingController();
  List<UserSearch> _results = [];
  List<UserSearch> _selected = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initiallyTagged);
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final users = await ApiService.searchUsers(query);
      final currentUserId = await ApiService.getUserId();
      setState(() {
        _results = users
            .map((u) => UserSearch(
                  userId: u['userId'] ?? 0,
                  username: u['username'] ?? '',
                  fullName: u['fullName'] ?? '',
                ))
            .where((u) => u.userId != (currentUserId ?? -1))
            .toList();
      });
    } catch (_) {
      setState(() => _results = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tag People'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Search users...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (q) => _search(q),
              ),
              const SizedBox(height: 12),
              if (_loading) const CircularProgressIndicator(),
              if (!_loading)
                ..._results.map((u) => CheckboxListTile(
                      value: _selected.any((sel) => sel.userId == u.userId),
                      title: Text(u.fullName),
                      subtitle: Text(u.username),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selected.add(u);
                          } else {
                            _selected.removeWhere((sel) => sel.userId == u.userId);
                          }
                        });
                      },
                    )),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: _selected.map((u) => Chip(label: Text(u.fullName))).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
