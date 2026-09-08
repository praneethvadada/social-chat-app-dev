import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Displays an image at its own natural aspect ratio — never stretches,
/// never force-crops. Width always fills the available space; height is
/// derived from the image's real dimensions (`width / (naturalW/naturalH)`),
/// so portrait, landscape, square, panoramic and tall images all lay out
/// correctly instead of every image being forced into the same fixed-height
/// `BoxFit.cover` box.
///
/// [maxHeight] is a generous safety cap only (not a crop) — if the natural
/// aspect ratio would make the image taller than this, it's scaled down
/// (via `BoxFit.contain`, so the *whole* image stays visible, just smaller
/// and centered) rather than left to blow out the surrounding layout.
///
/// One shared widget so the create-post preview and the published post
/// (feed card + post detail) render identically, per the "preview must
/// match the final post" requirement — see call sites in `post_card.dart`,
/// `post_detail_screen.dart`, and `create_post_screen.dart`.
class NaturalImage extends StatefulWidget {
  final ImageProvider provider;
  final double? maxHeight;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  /// Loading-placeholder height, used only until the image's real
  /// dimensions are known (first frame). Keep this close to a typical
  /// photo's height so there's minimal layout jump once it resolves.
  final double placeholderHeight;

  const NaturalImage({
    super.key,
    required this.provider,
    this.maxHeight,
    this.borderRadius,
    this.onTap,
    this.placeholderHeight = 240,
  });

  @override
  State<NaturalImage> createState() => _NaturalImageState();
}

class _NaturalImageState extends State<NaturalImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _naturalSize;
  bool _errored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant NaturalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _naturalSize = null;
      _errored = false;
      _resolve();
    }
  }

  void _resolve() {
    final newStream = widget.provider.resolve(createLocalImageConfiguration(context));
    if (newStream.key == _stream?.key) return;
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = newStream;
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _naturalSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
        });
      },
      onError: (error, stackTrace) {
        if (!mounted) return;
        setState(() => _errored = true);
      },
    );
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_errored) {
      content = Container(
        height: widget.placeholderHeight,
        color: AppColors.surface2,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: AppColors.mutedSolid, size: 32),
      );
    } else if (_naturalSize == null) {
      content = Container(
        height: widget.placeholderHeight,
        color: AppColors.surface2,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      content = LayoutBuilder(builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        double h = maxW * _naturalSize!.height / _naturalSize!.width;
        if (widget.maxHeight != null && h > widget.maxHeight!) {
          h = widget.maxHeight!;
        }
        return SizedBox(
          width: maxW,
          height: h,
          // contain, never cover — the whole image always stays visible,
          // never force-cropped or force-stretched.
          child: Image(image: widget.provider, fit: BoxFit.contain),
        );
      });
    }
    if (widget.borderRadius != null) {
      content = ClipRRect(borderRadius: widget.borderRadius!, child: content);
    }
    if (widget.onTap != null) {
      content = GestureDetector(onTap: widget.onTap, child: content);
    }
    return content;
  }
}
