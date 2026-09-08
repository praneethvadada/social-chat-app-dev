import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/selected_media.dart';
import '../services/media_service.dart';

class MediaPicker {
  final ImagePicker _picker = ImagePicker();

  static const int maxImagesPerPost = 20;

  /// [limit] caps how many the OS picker itself will let the user select in
  /// this one picking session — pass the number of slots actually still
  /// free (maxImagesPerPost minus what's already selected) so repeated
  /// "add more" picks can't push the post's total past the cap.
  Future<List<SelectedMedia>> pickImages({int? limit}) async {
    final List<XFile>? files = await _picker.pickMultiImage(imageQuality: 85, limit: limit);
    if (files == null) return [];
    final out = <SelectedMedia>[];
    for (final f in files) {
      final file = File(f.path);
      out.add(MediaService.fromFile(file, MediaType.image));
    }
    return out;
  }

  Future<SelectedMedia?> pickVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
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
    return MediaService.fromFile(File(file.path), MediaType.image);
  }

  Future<SelectedMedia?> takeVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.camera);
    if (file == null) return null;
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
}
