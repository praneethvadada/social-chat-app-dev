import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final String logoType; // 'png' or 'ico'
  const AppLogo({super.key, this.size = 72, this.logoType = 'png'});

  @override
  Widget build(BuildContext context) {
    final imagePath = logoType == 'ico' 
      ? 'assets/images/logo.ico' 
      : 'assets/images/logo.png';
    
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
