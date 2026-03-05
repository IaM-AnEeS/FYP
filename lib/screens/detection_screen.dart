import 'package:flutter/material.dart';

// Placeholder screen – actual object detection is handled by backend.

class ObjectDetectionScreen extends StatelessWidget {
  const ObjectDetectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Object Detection'),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Object detection is performed on the server.\n\nUse the camera/data upload feature to send images to backend.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

