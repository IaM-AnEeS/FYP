import 'package:flutter/material.dart';
// Navigation screen no longer directly constructs the camera screen.
// routing is handled via named routes in main.dart.

// GUI-only NavigationScreen. All camera, TTS, model and image-processing
// code removed. This file provides a simple UI skeleton for the Navigation
// screen with mode buttons and a camera-status placeholder.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  String selectedMode = 'Indoor';
  // UI-only state
  bool _showModeButtons = true;

  // navigation screen does not manage camera directly anymore; we push
  // a dedicated `CameraLiveScreen` which handles camera lifecycle.

  Widget _modeButton(String mode) {
    final bool selected = selectedMode == mode;
    final theme = Theme.of(context);
    return ElevatedButton(
      onPressed: () => setState(() => selectedMode = mode),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surface.withOpacity(0.9),
        foregroundColor:
            selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
      ),
      child: Text(mode),
    );
  }

  Widget _buildModeButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _modeButton('Indoor'),
        const SizedBox(width: 8),
        _modeButton('Outdoor'),
        const SizedBox(width: 8),
        _modeButton('SOS'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: Column(
        children: [
          if (_showModeButtons)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: _buildModeButtons(),
            ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  margin: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.navigation,
                          size: 64,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '15 meters',
                          style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.7), fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Large bottom control: navigate to live camera screen
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/detection');
                },
                icon: const Icon(Icons.mic),
                label: const Text('Tap to Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
