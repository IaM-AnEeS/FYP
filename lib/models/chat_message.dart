enum ChatRole {
  user,
  assistant,
}

class ChatMessage {
  final String text;
  final ChatRole role;
  final DateTime createdAt;

  const ChatMessage({
    required this.text,
    required this.role,
    required this.createdAt,
  });

  bool get isUser => role == ChatRole.user;
}
