import 'dart:async';

import 'package:flutter/material.dart';

enum NavigationVoiceCommandType {
  selectIndoor,
  selectOutdoor,
  startIndoorDetection,
  startOutdoorDetection,
  stopDetection,
}

class NavigationVoiceCommand {
  final NavigationVoiceCommandType type;

  const NavigationVoiceCommand(this.type);
}

class NavigationVoiceBridge {
  NavigationVoiceBridge._();

  static final NavigationVoiceBridge instance = NavigationVoiceBridge._();

  final StreamController<NavigationVoiceCommand> _controller =
      StreamController<NavigationVoiceCommand>.broadcast();

  final ValueNotifier<bool> navigationVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> detectionRunning = ValueNotifier<bool>(false);

  Stream<NavigationVoiceCommand> get commands => _controller.stream;

  void send(NavigationVoiceCommandType type) {
    if (_controller.isClosed) return;
    _controller.add(NavigationVoiceCommand(type));
  }

  void setNavigationVisible(bool visible) {
    if (navigationVisible.value == visible) return;
    navigationVisible.value = visible;
  }

  void setDetectionRunning(bool running) {
    if (detectionRunning.value == running) return;
    detectionRunning.value = running;
  }

  void dispose() {
    _controller.close();
  }
}
