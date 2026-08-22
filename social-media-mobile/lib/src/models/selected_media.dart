import 'dart:io';

enum MediaType { image, video }

class SelectedMedia {
  final String id;
  final File file;
  final MediaType type;
  final String? thumbnailPath;
  final Duration? duration;

  SelectedMedia({
    required this.id,
    required this.file,
    required this.type,
    this.thumbnailPath,
    this.duration,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': file.path,
        'type': type.name,
        'thumbnail': thumbnailPath,
        'duration': duration?.inMilliseconds,
      };
}
