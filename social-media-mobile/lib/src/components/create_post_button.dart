import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state_manager.dart';

class CreatePostButton extends ConsumerStatefulWidget {
  const CreatePostButton({super.key});

  @override
  ConsumerState<CreatePostButton> createState() => _CreatePostButtonState();
}

class _CreatePostButtonState extends ConsumerState<CreatePostButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.04,
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _ctl.forward();
  void _onTapUp(TapUpDetails _) => _ctl.reverse();
  void _onTapCancel() => _ctl.reverse();

  @override
  Widget build(BuildContext context) {
    final scale = 1 - _ctl.value;
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () {
        ref.read(appStateProvider.notifier).openModal(ModalScreen.createPost);
      },
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (context, child) => Transform.scale(
          scale: scale,
          child: child,
        ),
        child: RepaintBoundary(
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: theme.dividerColor.withAlpha((0.08 * 255).round()),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 60,
                        alignment: Alignment.center,
                        child: CustomPaint(
                          painter: _DashedRoundedRectPainter(
                            color: theme.dividerColor,
                            radius: 12,
                            strokeWidth: 1.5,
                          ),
                          child: SizedBox(
                            height: 60,
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add,
                                    color: theme.colorScheme.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Create a post',
                                    style: TextStyle(
                                      color: theme.textTheme.bodyMedium?.color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;

  _DashedRoundedRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    const dashWidth = 6.0;
    const dashSpace = 6.0;
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
