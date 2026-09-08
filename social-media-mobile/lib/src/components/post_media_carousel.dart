import 'package:flutter/material.dart';
import 'natural_image.dart';

/// Displays a post's images (and video thumbnails), 1 to N of them — the
/// single-item case defers entirely to [NaturalImage] (exact natural
/// aspect ratio, no cap needed since there's nothing to keep uniform for
/// swiping). 2+ images become a swipeable carousel with a "1/N" counter
/// and dot indicators, matching how every major app handles multi-image
/// posts: the carousel itself is a fixed height (swiping between pages of
/// different heights reads as broken, not as "preserving aspect ratio"),
/// but each image inside still uses BoxFit.contain — scaled down to fit,
/// never cropped, never stretched.
///
/// Used identically by the feed card and post detail screen so they can't
/// drift apart — see call sites in `post_card.dart` / `post_detail_screen.dart`.
class PostMediaCarousel extends StatefulWidget {
  final List<String> urls;
  /// Height cap for the single-image case (passed through to NaturalImage);
  /// also the fixed height used for the 2+ image carousel.
  final double maxHeight;
  final BorderRadius? borderRadius;
  final void Function(String url)? onTapImage;
  final void Function(String url)? onTapVideo;
  final Widget Function(String url)? videoThumbnailBuilder;
  final Widget? topLeftBadge;

  const PostMediaCarousel({
    super.key,
    required this.urls,
    this.maxHeight = 500,
    this.borderRadius,
    this.onTapImage,
    this.onTapVideo,
    this.videoThumbnailBuilder,
    this.topLeftBadge,
  });

  @override
  State<PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<PostMediaCarousel> {
  final _pageController = PageController();
  int _page = 0;

  bool _isVideo(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') || u.endsWith('.webm') || u.endsWith('.mov');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const SizedBox.shrink();

    if (widget.urls.length == 1) {
      final url = widget.urls.first;
      Widget content = _isVideo(url)
          ? (widget.videoThumbnailBuilder?.call(url) ?? const SizedBox.shrink())
          : NaturalImage(
              provider: NetworkImage(url),
              maxHeight: widget.maxHeight,
              onTap: widget.onTapImage != null ? () => widget.onTapImage!(url) : null,
            );
      if (_isVideo(url) && widget.onTapVideo != null) {
        content = GestureDetector(onTap: () => widget.onTapVideo!(url), child: content);
      }
      if (widget.borderRadius != null) {
        content = ClipRRect(borderRadius: widget.borderRadius!, child: content);
      }
      return widget.topLeftBadge == null
          ? content
          : Stack(children: [content, Positioned(top: 14, left: 14, child: widget.topLeftBadge!)]);
    }

    Widget carousel = SizedBox(
      height: widget.maxHeight,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final url = widget.urls[i];
              if (_isVideo(url)) {
                return GestureDetector(
                  onTap: widget.onTapVideo != null ? () => widget.onTapVideo!(url) : null,
                  child: widget.videoThumbnailBuilder?.call(url) ?? const SizedBox.shrink(),
                );
              }
              return GestureDetector(
                onTap: widget.onTapImage != null ? () => widget.onTapImage!(url) : null,
                child: Image.network(url, fit: BoxFit.contain, width: double.infinity),
              );
            },
          ),
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
              child: Text('${_page + 1}/${widget.urls.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
          if (widget.topLeftBadge != null) Positioned(top: 14, left: 14, child: widget.topLeftBadge!),
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.urls.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (widget.borderRadius != null) {
      carousel = ClipRRect(borderRadius: widget.borderRadius!, child: carousel);
    }
    return carousel;
  }
}
