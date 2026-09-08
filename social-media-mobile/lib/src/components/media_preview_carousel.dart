import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../models/selected_media.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// Reads a picked image's display bytes: the crop result if the user
/// cropped it, otherwise the original file — via XFile.readAsBytes(),
/// which (unlike dart:io's File/FileImage) works on Flutter Web as well as
/// mobile. Shared by the thumbnail strip below and the large preview in
/// create_post_screen.dart, so both always agree on what's about to post.
Future<Uint8List> loadSelectedMediaBytes(SelectedMedia m) async {
  if (m.croppedBytes != null) return m.croppedBytes!;
  return XFile(m.file.path).readAsBytes();
}

class MediaPreviewCarousel extends StatelessWidget {
  final List<SelectedMedia> items;
  final void Function(SelectedMedia) onRemove;
  final void Function(SelectedMedia) onTap;
  /// Opens the full "how it'll look in the post" preview + Crop button —
  /// only reachable via this explicit edit icon (images only; there's
  /// nothing to crop on a video), never shown automatically.
  final void Function(SelectedMedia)? onEdit;

  const MediaPreviewCarousel({
    super.key,
    required this.items,
    required this.onRemove,
    required this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 120,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final m = items[index];
          return RepaintBoundary(
            child: GestureDetector(
              onTap: () => onTap(m),
              child: Stack(
                children: [
                  Container(
                    width: 160,
                    height: 100,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.surface2,
                    ),
                    // FileImage/DecorationImage(FileImage(...)) is
                    // dart:io-based and doesn't work on Flutter Web — read
                    // via the same cross-platform helper the large preview
                    // uses instead. This is a small fixed-size selector
                    // chip, not the "how it'll look in the post" preview,
                    // so BoxFit.cover here is intentional (matches
                    // Instagram/Twitter's own thumbnail-strip treatment) —
                    // the uncropped, natural-aspect preview lives
                    // separately, above this strip.
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (m.type == MediaType.image)
                          FutureBuilder<Uint8List>(
                            future: loadSelectedMediaBytes(m),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              }
                              return Image.memory(snapshot.data!, fit: BoxFit.cover, width: 160, height: 100);
                            },
                          ),
                        if (m.type == MediaType.video)
                          Container(
                            decoration: BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                            child: const Padding(
                              padding: EdgeInsets.all(6.0),
                              child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: GestureDetector(
                      onTap: () => onRemove(m),
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ),
                  if (m.type == MediaType.video && m.duration != null)
                    Positioned(
                      left: 8,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(6)),
                        child: Text(_formatDuration(m.duration!), style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  if (m.type == MediaType.image && onEdit != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: GestureDetector(
                        onTap: () => onEdit!(m),
                        child: Container(
                          decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Padding(
                            padding: EdgeInsets.all(5.0),
                            child: Icon(Icons.edit, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: items.length,
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
