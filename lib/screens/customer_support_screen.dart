import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../Services/support_chat_service.dart';
import '../Services/voice_assistant_service.dart';

class CustomerSupportScreen extends StatefulWidget {
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  const CustomerSupportScreen({super.key});

  @override
  State<CustomerSupportScreen> createState() => _CustomerSupportScreenState();
}

class _CustomerSupportScreenState extends State<CustomerSupportScreen> {
  final SupportChatService _supportChatService = SupportChatService();
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService.instance;
  final stt.SpeechToText _localSpeech = stt.SpeechToText();

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const Duration _voiceListenFor = Duration(seconds: 45);
  static const Duration _voicePauseFor = Duration(seconds: 3);

  static const List<String> _goHomeCommandPhrases = <String>[
    'go home',
    'go to home',
    'go to home screen',
    'home screen',
    'open home',
  ];

  String? _conversationId;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  bool _isListeningForVoice = false;
  bool _localSpeechReady = false;
  bool _voiceCommandHandled = false;

  String _voiceStatus =
      'Tap in the chat area and speak your issue. Say "go home" to return.';
  String _lastSpokenText = '';

  Timer? _voiceTimeoutTimer;

  @override
  void initState() {
    super.initState();
    CustomerSupportScreen.isActive.value = true;
    unawaited(_bootstrapConversation());
  }

  @override
  void dispose() {
    CustomerSupportScreen.isActive.value = false;
    _voiceTimeoutTimer?.cancel();
    _voiceTimeoutTimer = null;
    unawaited(_localSpeech.stop());
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapConversation() async {
    try {
      final id = await _supportChatService.ensureConversationForCurrentUser();
      await _supportChatService.markReadByUser(id);

      if (!mounted) return;
      setState(() {
        _conversationId = id;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _sendMessage({String? overrideText}) async {
    final conversationId = _conversationId;
    final text = (overrideText ?? _controller.text).trim();

    if (conversationId == null || text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _controller.clear();
    });

    try {
      await _supportChatService.sendUserMessage(
        conversationId: conversationId,
        text: text,
      );
      await _supportChatService.markReadByUser(conversationId);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _handleScreenTapForVoiceInput() async {
    if (_isLoading || _isSending || _isListeningForVoice) return;
    if (_error != null || _conversationId == null) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (!mounted) return;
      setState(() {
        _voiceStatus = 'Microphone permission is required for voice message.';
      });
      await _voiceAssistant.speak(
        'Microphone permission is required for support voice messages.',
        resumeWakeListening: false,
        forceWhenDisabled: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListeningForVoice = true;
      _voiceCommandHandled = false;
      _lastSpokenText = '';
      _voiceStatus =
          'Tell me your issue. I will send it to admin. You can also say go home.';
    });

    await _voiceAssistant.speak(
      'Tell me your issue. I will send it to admin. You can also say go home.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted || !_isListeningForVoice) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _listenForVoiceMessage();
  }

  Future<void> _listenForVoiceMessage() async {
    if (!_isListeningForVoice || !mounted) return;

    if (!_localSpeechReady) {
      _localSpeechReady = await _localSpeech.initialize(
        onStatus: _onLocalSpeechStatus,
        onError: _onLocalSpeechError,
        debugLogging: false,
      );
    }

    if (!_localSpeechReady) {
      if (!mounted) return;
      setState(() {
        _isListeningForVoice = false;
        _voiceStatus = 'Voice recognition is unavailable on this device right now.';
      });
      return;
    }

    _voiceTimeoutTimer?.cancel();
    _voiceTimeoutTimer = Timer(
      _voiceListenFor + const Duration(seconds: 2),
      () {
        unawaited(_finishVoiceListening(noVoiceHeard: true));
      },
    );

    try {
      await _localSpeech.listen(
        onResult: _onLocalSpeechResult,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        listenFor: _voiceListenFor,
        pauseFor: _voicePauseFor,
        localeId: 'en_US',
      );

      if (!mounted) return;
      setState(() {
        _voiceStatus =
            'Listening... speak your issue now. Long or short messages are both fine.';
      });
    } catch (_) {
      await _finishVoiceListening(
        noVoiceHeard: false,
        customStatus: 'Could not start listening. Tap and try again.',
      );
    }
  }

  void _onLocalSpeechResult(dynamic result) {
    final heardText = result.recognizedWords.trim();
    if (heardText.isEmpty || !mounted || !_isListeningForVoice) {
      return;
    }

    setState(() {
      _lastSpokenText = heardText;
    });

    if (!_voiceCommandHandled && _isGoHomeCommand(heardText)) {
      final normalized = _normalizeVoiceText(heardText);
      final shortPhrase = normalized.split(' ').length <= 5;
      if (result.finalResult || shortPhrase) {
        _voiceCommandHandled = true;
        unawaited(_handleGoHomeVoiceCommand());
        return;
      }
    }

    if (result.finalResult && !_voiceCommandHandled) {
      _voiceCommandHandled = true;
      unawaited(
        _finishVoiceListening(
          noVoiceHeard: false,
          sendRecognizedText: true,
          recognizedText: heardText,
        ),
      );
    }
  }

  void _onLocalSpeechStatus(String status) {
    if (!_isListeningForVoice || _voiceCommandHandled) return;
    if (status == 'done' || status == 'notListening') {
      unawaited(
        _finishVoiceListening(
          noVoiceHeard: _lastSpokenText.trim().isEmpty,
          sendRecognizedText: _lastSpokenText.trim().isNotEmpty,
          recognizedText: _lastSpokenText,
        ),
      );
    }
  }

  void _onLocalSpeechError(dynamic error) {
    if (!_isListeningForVoice || _voiceCommandHandled) return;
    unawaited(
      _finishVoiceListening(
        noVoiceHeard: false,
        customStatus: 'Could not understand that. Tap and try again.',
      ),
    );
  }

  Future<void> _handleGoHomeVoiceCommand() async {
    await _finishVoiceListening(
      noVoiceHeard: false,
      customStatus: 'Going home...',
    );

    await _voiceAssistant.speak(
      'Going to home screen.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (_) => false);
  }

  Future<void> _finishVoiceListening({
    required bool noVoiceHeard,
    bool sendRecognizedText = false,
    String? recognizedText,
    String? customStatus,
  }) async {
    _voiceTimeoutTimer?.cancel();
    _voiceTimeoutTimer = null;

    try {
      if (_localSpeech.isListening) {
        await _localSpeech.stop();
      }
    } catch (_) {
      // Ignore stop errors to keep UX smooth.
    }

    if (!mounted) return;

    setState(() {
      _isListeningForVoice = false;
      if (customStatus != null) {
        _voiceStatus = customStatus;
      } else if (noVoiceHeard) {
        _voiceStatus =
            'No voice message detected. Tap in chat area and try again.';
      } else {
        _voiceStatus = 'Voice message captured.';
      }
    });

    if (!sendRecognizedText) return;

    final messageText = (recognizedText ?? _lastSpokenText).trim();
    if (messageText.isEmpty) return;

    if (_isGoHomeCommand(messageText)) {
      await _handleGoHomeVoiceCommand();
      return;
    }

    if (mounted) {
      setState(() {
        _voiceStatus = 'Sending your voice message to admin...';
      });
    }

    await _sendMessage(overrideText: messageText);

    if (mounted) {
      setState(() {
        _voiceStatus =
            'Voice message sent to admin. Tap in chat area to speak again.';
      });
    }
  }

  bool _isGoHomeCommand(String rawText) {
    final normalized = _normalizeVoiceText(rawText);
    for (final phrase in _goHomeCommandPhrases) {
      if (normalized == phrase || normalized.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  String _normalizeVoiceText(String rawText) {
    return rawText
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 160,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Support')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Support')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Unable to start support chat.\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final conversationId = _conversationId;
    if (conversationId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Support')),
        body: const Center(child: Text('Conversation unavailable')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Support'),
        actions: [
          IconButton(
            tooltip: 'Tap to Speak',
            onPressed: _isListeningForVoice ? null : _handleScreenTapForVoiceInput,
            icon: Icon(
              _isListeningForVoice ? Icons.mic : Icons.mic_none,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _supportChatService.conversationsRef
                .doc(conversationId)
                .snapshots(),
            builder: (context, snapshot) {
              final status =
                  (snapshot.data?.data()?['status']?.toString() ?? 'open')
                      .toLowerCase();
              final statusText = status == 'resolved' ? 'Resolved' : 'Open';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Conversation status: $statusText',
                  style: theme.textTheme.bodySmall,
                ),
              );
            },
          ),
        ),
      ),
      body: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleScreenTapForVoiceInput,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isListeningForVoice
                        ? 'Listening for your message...'
                        : 'Tap here and speak your issue to send it to admin.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _voiceStatus,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_lastSpokenText.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Heard: "$_lastSpokenText"',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleScreenTapForVoiceInput,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _supportChatService.watchMessages(conversationId),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  if (docs.isEmpty) {
                    return ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(14),
                      children: [
                        _systemCard(
                          context,
                          'Welcome to Customer Support. Tap and speak anything that is not working, and it will be sent to admin.',
                        ),
                      ],
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(_supportChatService.markReadByUser(conversationId));
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final senderRole =
                          (data['senderRole']?.toString() ?? 'admin').toLowerCase();
                      final isUser = senderRole == 'user';
                      final isSystem = senderRole == 'system';
                      final text = data['text']?.toString() ?? '';
                      final createdAt = _formatTime(data['createdAt']);

                      if (isSystem) {
                        return _systemCard(context, text);
                      }

                      return Align(
                        alignment:
                            isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          constraints: const BoxConstraints(maxWidth: 360),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(isUser ? 14 : 0),
                              bottomRight: Radius.circular(isUser ? 0 : 14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                text,
                                style: TextStyle(
                                  color: isUser
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                createdAt,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isUser
                                      ? theme.colorScheme.onPrimary
                                          .withValues(alpha: 0.8)
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Type your issue or tap and speak...',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isSending ? null : () => _sendMessage(),
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: theme.colorScheme.primary,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemCard(BuildContext context, String message) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.support_agent_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  String _formatTime(dynamic value) {
    final date = _toDateTime(value);
    if (date == null) return '';

    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
