import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class ChatImageEditor extends StatefulWidget {
  final Uint8List imageBytes;

  const ChatImageEditor({super.key, required this.imageBytes});

  @override
  State<ChatImageEditor> createState() => _ChatImageEditorState();
}

class _ChatImageEditorState extends State<ChatImageEditor> {
  final _controller = CropController();
  bool _isCropping = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text('Edit Image', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: Icon(Icons.close, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
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
          )
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Crop(
              image: widget.imageBytes,
              controller: _controller,
              withCircleUi: false,
              initialSize: 0.9,
              // Freeform aspect ratio for chat attachments
              onCropped: (bytes) {
                if (!mounted) return;
                Navigator.of(context).pop<Uint8List>(bytes);
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
