import 'dart:io';
import 'package:flutter/material.dart';
import 'package:social_chat_app/src/theme/colors.dart';

// Video trimming UI removed due to incompatible `video_trimmer` plugin.
// This stub preserves the route so other code can navigate here without
// causing analyzer/build errors. If you want trimming back, re-add a
// compatible trimming implementation.
class ChatVideoTrimmer extends StatelessWidget {
  final File? videoFile;
  const ChatVideoTrimmer({super.key, this.videoFile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trim Video')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_file, size: 72, color: AppColors.mutedSolid),
              const SizedBox(height: 12),
              const Text('Video trimming is currently unavailable.', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
