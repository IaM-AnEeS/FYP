import 'package:flutter/material.dart';

// Simplified placeholder screen; backend handles camera, detection, and TTS.

class CameraLiveScreen extends StatelessWidget {
  final String mode; // mode is kept for compatibility but not used
  const CameraLiveScreen({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Capture'),
        backgroundColor: theme.colorScheme.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'This screen would normally show a live camera feed and run detection locally.\n\nAll computation has been moved to the backend via Flask.\n\nUse a network call or image picker here to send images to the server.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}



