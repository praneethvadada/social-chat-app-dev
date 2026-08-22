import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../models/selected_media.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import '../../services/status_api.dart';

/// S1 status composer: text (with background colour) or image/video.
class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  static const _backgrounds = <String>[
    '#4CAF50', '#2196F3', '#9C27B0', '#F44336',
    '#FF9800', '#009688', '#3F51B5', '#212121',
  ];

  final _controller = TextEditingController();
  String _background = _backgrounds.first;
  File? _mediaFile;
  bool _isVideo = false;
  bool _posting = false;
  double _uploadProgress = 0;

  /// S4 audience. CONTACTS needs no list; EXCEPT/ONLY carry selected users.
  String _privacyType = 'CONTACTS';
  final Map<int, Map<String, dynamic>> _audience = {};

  String get _audienceLabel {
    switch (_privacyType) {
      case 'EXCEPT':
        return 'Contacts except ${_audience.length}';
      case 'ONLY':
        return 'Only ${_audience.length} selected';
      default:
        return 'My Contacts';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _color(String hex) =>
      Color(int.parse('FF${hex.substring(1)}', radix: 16));

  Future<void> _pick(bool video) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = video
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      setState(() {
        _mediaFile = File(picked.path);
        _isVideo = video;
      });
    } catch (e) {
      Fluttertoast.showToast(msg: 'Could not open gallery');
    }
  }


  /// Spec §F: choose who can see this status BEFORE posting.
  Future<void> _chooseAudience() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Status Audience',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            RadioListTile<String>(
              value: 'CONTACTS',
              groupValue: _privacyType,
              title: const Text('My Contacts'),
              subtitle: const Text('Everyone who follows you'),
              onChanged: (v) => Navigator.pop(sheet, v),
            ),
            RadioListTile<String>(
              value: 'EXCEPT',
              groupValue: _privacyType,
              title: const Text('My Contacts Except...'),
              subtitle: const Text('Hide from specific people'),
              onChanged: (v) => Navigator.pop(sheet, v),
            ),
            RadioListTile<String>(
              value: 'ONLY',
              groupValue: _privacyType,
              title: const Text('Only Share With...'),
              subtitle: const Text('Visible to selected people only'),
              onChanged: (v) => Navigator.pop(sheet, v),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;
    if (choice == 'CONTACTS') {
      setState(() {
        _privacyType = choice;
        _audience.clear();
      });
      return;
    }
    // EXCEPT / ONLY need a people list to mean anything.
    final confirmed = await _pickPeople(choice);
    if (confirmed) setState(() => _privacyType = choice);
  }

  Future<bool> _pickPeople(String mode) async {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> results = [];
    Timer? debounce;
    final selected = Map<int, Map<String, dynamic>>.from(_audience);

    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(sheet).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                      mode == 'ONLY' ? 'Only Share With' : 'Hide Status From',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'Search contacts...',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (q) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 400),
                          () async {
                        if (q.trim().isEmpty) {
                          setSheet(() => results = []);
                          return;
                        }
                        try {
                          final users = await ApiService.searchUsers(q.trim());
                          setSheet(() => results = users);
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
                        value: selected.containsKey(uid),
                        onChanged: (_) => setSheet(() {
                          selected.containsKey(uid)
                              ? selected.remove(uid)
                              : selected[uid] = u;
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
                            : () => Navigator.pop(sheet, true),
                        child: Text('Done (${selected.length})'),
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
    if (done == true) {
      setState(() {
        _audience
          ..clear()
          ..addAll(selected);
      });
      return true;
    }
    return false;
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (_mediaFile == null && text.isEmpty) {
      Fluttertoast.showToast(msg: 'Write something or pick a photo');
      return;
    }

    setState(() => _posting = true);
    try {
      if (_mediaFile != null) {
        // Reuse the existing S3 upload pipeline used by posts/chat media.
        final media = SelectedMedia(
          id: const Uuid().v4(),
          file: _mediaFile!,
          type: _isVideo ? MediaType.video : MediaType.image,
        );
        final url = await MediaService.uploadMedia(
          media,
          (p) => setState(() => _uploadProgress = p),
        );
        await StatusApi.createMedia(
            mediaUrl: url,
            isVideo: _isVideo,
            caption: text,
            privacyType: _privacyType,
            audienceUserIds: _audience.keys.toList());
      } else {
        await StatusApi.createText(
            content: text,
            backgroundColor: _background,
            privacyType: _privacyType,
            audienceUserIds: _audience.keys.toList());
      }

      if (!mounted) return;
      Fluttertoast.showToast(msg: 'Status posted - disappears in 24 hours');
      Navigator.of(context).pop(true);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Couldn\'t post status');
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = _mediaFile != null;

    return Scaffold(
      backgroundColor: hasMedia ? Colors.black : _color(_background),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Add Status'),
        actions: [
          if (!_posting)
            TextButton(
              onPressed: _post,
              child: const Text('Post',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: hasMedia
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_isVideo)
                        const Center(
                          child: Icon(Icons.play_circle_outline,
                              color: Colors.white54, size: 72),
                        )
                      else
                        Image.file(_mediaFile!, fit: BoxFit.contain),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => setState(() => _mediaFile = null),
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        maxLength: 1000,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: "What's on your mind?",
                          hintStyle:
                              TextStyle(color: Colors.white54, fontSize: 22),
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
          ),
          if (_posting && _uploadProgress > 0 && _uploadProgress < 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _uploadProgress),
                  const SizedBox(height: 4),
                  Text('Uploading ${(_uploadProgress * 100).round()}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          if (hasMedia)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Add a caption...',
                  hintStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          // S4: who will see this (spec §F, chosen before posting)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: Icon(
                    _privacyType == 'CONTACTS'
                        ? Icons.people
                        : _privacyType == 'ONLY'
                            ? Icons.lock
                            : Icons.person_off,
                    size: 16,
                    color: Colors.white),
                backgroundColor: Colors.black26,
                label: Text(_audienceLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                onPressed: _chooseAudience,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Photo',
                    icon: const Icon(Icons.image, color: Colors.white),
                    onPressed: () => _pick(false),
                  ),
                  IconButton(
                    tooltip: 'Video',
                    icon: const Icon(Icons.videocam, color: Colors.white),
                    onPressed: () => _pick(true),
                  ),
                  if (!hasMedia)
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: _backgrounds.map((hex) {
                            final selected = hex == _background;
                            return GestureDetector(
                              onTap: () => setState(() => _background = hex),
                              child: Container(
                                width: 28,
                                height: 28,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: _color(hex),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white24,
                                      width: selected ? 3 : 1),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
