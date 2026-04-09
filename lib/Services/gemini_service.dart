import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/ai_assistant_config.dart';
import '../models/chat_message.dart';

class GeminiServiceException implements Exception {
  final String message;

  const GeminiServiceException(this.message);

  @override
  String toString() => message;
}

class GeminiService {
  final http.Client _client;

  GeminiService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> sendMessage({
    required String userMessage,
    required List<ChatMessage> history,
    String? currentScreen,
  }) async {
    final trimmedMessage = userMessage.trim();
    if (trimmedMessage.isEmpty) {
      throw const GeminiServiceException('Please type a message first.');
    }

    if (AIAssistantConfig.geminiApiKey.trim().isEmpty) {
      throw const GeminiServiceException(
        'Gemini API key is missing. Add it in ai_assistant_config.dart.',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/${AIAssistantConfig.geminiModel}:generateContent?key=${AIAssistantConfig.geminiApiKey}',
    );

    final payload = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': AIAssistantConfig.systemPrompt},
        ],
      },
      'contents': _buildConversation(history),
      'generationConfig': {
        'temperature': 0.2,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 300,
      },
    };

    if (currentScreen != null && currentScreen.trim().isNotEmpty) {
      payload['contents'].insert(0, {
        'role': 'user',
        'parts': [
          {
            'text':
                'Current app screen: $currentScreen. Keep guidance aligned to this screen and nearby app flows.',
          },
        ],
      });
    }

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(AIAssistantConfig.requestTimeout);
    } on SocketException {
      throw const GeminiServiceException(
        'No internet connection. Please check Wi-Fi/mobile data and try again.',
      );
    } on TimeoutException {
      throw const GeminiServiceException(
        'Request timed out. Please try again in a moment.',
      );
    } catch (_) {
      throw const GeminiServiceException(
        'Could not reach the assistant service. Please try again.',
      );
    }

    if (response.statusCode != 200) {
      final errorMessage = _extractApiError(response.body);
      throw GeminiServiceException(
        'Assistant service failed (${response.statusCode}): $errorMessage',
      );
    }

    final String reply = _extractReplyText(response.body);
    if (reply.trim().isEmpty) {
      throw const GeminiServiceException(
        'Assistant returned an empty response. Please ask again.',
      );
    }

    return reply.trim();
  }

  List<Map<String, dynamic>> _buildConversation(List<ChatMessage> history) {
    const int maxMessages = 12;
    final recent = history.length > maxMessages
        ? history.sublist(history.length - maxMessages)
        : history;

    return recent
        .map(
          (message) => {
            'role': message.isUser ? 'user' : 'model',
            'parts': [
              {'text': message.text},
            ],
          },
        )
        .toList();
  }

  String _extractReplyText(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return '';

      final firstCandidate = candidates.first as Map<String, dynamic>;
      final content = firstCandidate['content'] as Map<String, dynamic>?;
      if (content == null) return '';

      final parts = content['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return '';

      final textParts = <String>[];
      for (final part in parts) {
        if (part is Map<String, dynamic>) {
          final text = part['text'];
          if (text is String && text.trim().isNotEmpty) {
            textParts.add(text.trim());
          }
        }
      }

      return textParts.join('\n').trim();
    } catch (_) {
      return '';
    }
  }

  String _extractApiError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      if (error == null) return 'Unknown API error';
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
      return 'Unknown API error';
    } catch (_) {
      return 'Unknown API error';
    }
  }

  void dispose() {
    _client.close();
  }
}
