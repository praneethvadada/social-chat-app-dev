import 'dart:io';
import 'dart:async';

import 'package:uuid/uuid.dart';
import '../models/selected_media.dart';
import 'api_service.dart';

class MediaService {
  static final _uuid = Uuid();

  static Future<String> uploadMedia(SelectedMedia media, void Function(double) onProgress) async {
    try {
      onProgress(0.3);
      // If the user explicitly cropped this image, upload the crop result
      // instead of the original file — see SelectedMedia.croppedBytes.
      final url = media.croppedBytes != null
          ? await ApiService.uploadImageBytes(media.croppedBytes!)
          : await ApiService.uploadImage(media.file.path);
      onProgress(1.0);
      return url;
    } catch (e) {
      onProgress(0.0);
      rethrow;
    }
  }

  static SelectedMedia fromFile(File file, MediaType type, {String? thumb, Duration? duration}) {
    return SelectedMedia(id: _uuid.v4(), file: file, type: type, thumbnailPath: thumb, duration: duration);
  }
}
