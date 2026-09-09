import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/selected_media.dart';
import '../services/media_service.dart';

/// Thrown when a picked file exceeds [MediaPicker.maxFileSizeBytes] — the
/// UI catches this to show a friendly message instead of letting the
/// upload silently fail later (either against the backend's own
/// spring.servlet.multipart.max-file-size, or nginx's client_max_body_size
/// in front of it).
class MediaTooLargeException implements Exception {
  final String fileName;
  final int sizeBytes;
  const MediaTooLargeException(this.fileName, this.sizeBytes);
}

/// Result of a multi-image pick: the files under the cap, plus the names of
/// any that were skipped for being too large (so the caller can tell the
/// user exactly what didn't make it in, rather than silently dropping it).
class ImagePickResult {
  final List<SelectedMedia> items;
  final List<String> skippedForSize;
  const ImagePickResult(this.items, this.skippedForSize);
}

class MediaPicker {
  final ImagePicker _picker = ImagePicker();

  static const int maxImagesPerPost = 20;

  // Matches the backend's spring.servlet.multipart.max-file-size (100MB,
  // set in social-service's application.properties / application-prod
  // .properties) and the VPS nginx client_max_body_size in front of it —
  // keep these three in sync if either one ever changes.
  static const int maxFileSizeBytes = 100 * 1024 * 1024;
  static const String maxFileSizeLabel = '100 MB';

  /// [limit] caps how many the OS picker itself will let the user select in
  /// this one picking session — pass the number of slots actually still
  /// free (maxImagesPerPost minus what's already selected) so repeated
  /// "add more" picks can't push the post's total past the cap.
  Future<ImagePickResult> pickImages({int? limit}) async {
    final List<XFile>? files = await _picker.pickMultiImage(imageQuality: 85, limit: limit);
    if (files == null) return const ImagePickResult([], []);
    final out = <SelectedMedia>[];
    final skipped = <String>[];
    for (final f in files) {
      if (await _exceedsSizeCap(f)) {
        skipped.add(f.name);
        continue;
      }
      final file = File(f.path);
      out.add(MediaService.fromFile(file, MediaType.image));
    }
    return ImagePickResult(out, skipped);
  }

  Future<SelectedMedia?> pickVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    await _throwIfTooLarge(file);
    final f = File(file.path);
    Duration? dur;
    try {
      final controller = VideoPlayerController.file(f);
      await controller.initialize();
      dur = controller.value.duration;
      await controller.dispose();
    } catch (_) {}
    return MediaService.fromFile(f, MediaType.video, duration: dur);
  }

  Future<SelectedMedia?> takePhoto() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return null;
    await _throwIfTooLarge(file);
    return MediaService.fromFile(File(file.path), MediaType.image);
  }

  Future<SelectedMedia?> takeVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.camera);
    if (file == null) return null;
    await _throwIfTooLarge(file);
    final f = File(file.path);
    Duration? dur;
    try {
      final controller = VideoPlayerController.file(f);
      await controller.initialize();
      dur = controller.value.duration;
      await controller.dispose();
    } catch (_) {}
    return MediaService.fromFile(f, MediaType.video, duration: dur);
  }

  // XFile.length() works identically on web and mobile (unlike dart:io's
  // File.length(), which throws on web) — this is checked before ever
  // constructing a File, so the size check itself is web-safe too.
  Future<bool> _exceedsSizeCap(XFile f) async => await f.length() > maxFileSizeBytes;

  Future<void> _throwIfTooLarge(XFile f) async {
    final size = await f.length();
    if (size > maxFileSizeBytes) {
      throw MediaTooLargeException(f.name, size);
    }
  }
}
