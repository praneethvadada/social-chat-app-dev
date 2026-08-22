import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class ProfileImageCropper extends StatefulWidget {
  final Uint8List imageBytes;

  const ProfileImageCropper({super.key, required this.imageBytes});

  @override
  State<ProfileImageCropper> createState() => _ProfileImageCropperState();
}

class _ProfileImageCropperState extends State<ProfileImageCropper> {
  final _controller = CropController();
  bool _isCropping = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: theme.iconTheme,
        title: Text(
          'Crop Profile Photo',
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isCropping
                ? null
                : () {
                    setState(() => _isCropping = true);
                    _controller.crop();
                  },
            child: const Text('Done'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Crop(
              image: widget.imageBytes,
              controller: _controller,
              aspectRatio: 1,
              initialSize: 0.8,
              cornerDotBuilder: (size, edgeAlignment) => Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              onCropped: (croppedBytes) {
                if (!mounted) return;
                Navigator.of(context).pop<Uint8List>(croppedBytes);
              },
            ),
          ),
          if (_isCropping)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
