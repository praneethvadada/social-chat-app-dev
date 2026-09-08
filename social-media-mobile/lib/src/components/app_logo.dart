import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final String logoType; // 'webp' (default, the real Revolution Chat mark), 'png', or 'ico'
  const AppLogo({super.key, this.size = 72, this.logoType = 'webp'});

  @override
  Widget build(BuildContext context) {
    final imagePath = switch (logoType) {
      'ico' => 'assets/images/logo.ico',
      'png' => 'assets/images/logo.png',
      _ => 'assets/images/logo.webp',
    };

    return RepaintBoundary(
      child: Image.asset(
        imagePath,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
