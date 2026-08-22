import 'package:flutter/material.dart';

import '../models/selected_media.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class MediaPreviewCarousel extends StatelessWidget {
  final List<SelectedMedia> items;
  final void Function(SelectedMedia) onRemove;
  final void Function(SelectedMedia) onTap;

  const MediaPreviewCarousel({super.key, required this.items, required this.onRemove, required this.onTap});

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
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.surface2,
                      image: m.type == MediaType.image
                          ? DecorationImage(image: FileImage(m.file), fit: BoxFit.cover)
                          : null,
                    ),
                    child: m.type == MediaType.video
                        ? Center(
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                              child: const Padding(
                                padding: EdgeInsets.all(6.0),
                                child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
                              ),
                            ),
                          )
                        : null,
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
