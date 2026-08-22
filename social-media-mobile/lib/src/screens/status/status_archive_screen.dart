import 'package:flutter/material.dart';

import '../../models/status.dart';
import '../../services/status_api.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// S4 (§R): the owner's expired statuses.
///
/// Archive is strictly private - expired statuses never become visible to
/// anyone else again, and the backend has no endpoint to read someone else's.
class StatusArchiveScreen extends StatefulWidget {
  const StatusArchiveScreen({super.key});

  @override
  State<StatusArchiveScreen> createState() => _StatusArchiveScreenState();
}

class _StatusArchiveScreenState extends State<StatusArchiveScreen> {
  List<StatusItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await StatusApi.fetchArchive();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _bg(StatusItem s) {
    final hex = s.backgroundColor;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return AppColors.text;
  }

  String _audienceLabel(String privacy) {
    switch (privacy) {
      case 'ONLY':
        return 'Shared with selected';
      case 'EXCEPT':
        return 'Hidden from some';
      default:
        return 'My contacts';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Status Archive')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No archived statuses yet.\n\nStatuses move here after they expire, and only you can see them.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final s = _items[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: s.isText || s.mediaUrl == null
                                ? Container(
                                    color: _bg(s),
                                    padding: const EdgeInsets.all(6),
                                    alignment: Alignment.center,
                                    child: Text(
                                      s.content ?? '',
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11),
                                    ),
                                  )
                                : Image.network(s.mediaUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                        color: AppColors.border,
                                        child: const Icon(Icons.broken_image))),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.visibility, size: 11),
                            const SizedBox(width: 3),
                            Text('${s.viewCount}',
                                style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                        Text(_audienceLabel(s.privacyType),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 9, color: Theme.of(context).hintColor)),
                      ],
                    );
                  },
                ),
    );
  }
}
