import 'package:flutter/material.dart';

typedef TabChanged = void Function(int index);

class SegmentTabs extends StatelessWidget {
  final List<String> labels;
  final int currentIndex;
  final TabChanged onChanged;

  const SegmentTabs({super.key, required this.labels, required this.currentIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(labels.length, (i) {
            final active = i == currentIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Semantics(
                  button: true,
                  label: labels[i],
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      style: TextStyle(color: active ? primary : theme.textTheme.bodyMedium?.color, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        Row(
          children: List.generate(labels.length, (i) {
            final active = i == currentIndex;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 3,
                decoration: BoxDecoration(
                  color: active ? primary : Colors.transparent,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
