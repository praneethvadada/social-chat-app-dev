import 'dart:io';
import 'dart:typed_data';

enum MediaType { image, video }

class SelectedMedia {
  final String id;
  final File file;
  final MediaType type;
  final String? thumbnailPath;
  final Duration? duration;
  /// Set only after the user explicitly crops this image in the create-post
  /// screen (see PostImageCropper) — when present, this is what gets
  /// previewed and uploaded instead of [file]'s original bytes. `file`
  /// itself is never mutated (crop is opt-in and reversible: removing this
  /// falls back to the original). Bytes rather than a rewritten temp file
  /// so this works identically on web, where there's no filesystem to
  /// write a new file to.
  final Uint8List? croppedBytes;

  SelectedMedia({
    required this.id,
    required this.file,
    required this.type,
    this.thumbnailPath,
    this.duration,
    this.croppedBytes,
  });

  SelectedMedia copyWith({Uint8List? croppedBytes}) => SelectedMedia(
        id: id,
        file: file,
        type: type,
        thumbnailPath: thumbnailPath,
        duration: duration,
        croppedBytes: croppedBytes ?? this.croppedBytes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': file.path,
        'type': type.name,
        'thumbnail': thumbnailPath,
        'duration': duration?.inMilliseconds,
      };
}
