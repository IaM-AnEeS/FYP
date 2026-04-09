import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SupportChatService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  SupportChatService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get conversationsRef =>
      _db.collection('support_conversations');

  CollectionReference<Map<String, dynamic>> messagesRef(String conversationId) =>
      conversationsRef.doc(conversationId).collection('support_messages');

  Future<String> ensureConversationForCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'No signed-in user found.';
    }

    return ensureConversationForUser(
      userId: user.uid,
      userEmail: user.email ?? '',
      userName: user.displayName ?? '',
    );
  }

  Future<String> ensureConversationForUser({
    required String userId,
    required String userEmail,
    required String userName,
  }) async {
    final docRef = conversationsRef.doc(userId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      await docRef.set({
        'userId': userId,
        'userEmail': userEmail,
        'userName': userName,
        'status': 'open',
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderRole': 'system',
        'unreadByAdmin': false,
        'unreadByUser': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await docRef.set({
        'userEmail': userEmail,
        'userName': userName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return userId;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchConversations() {
    return conversationsRef.orderBy('lastMessageAt', descending: true).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String conversationId) {
    return messagesRef(conversationId).orderBy('createdAt').snapshots();
  }

  Future<void> sendUserMessage({
    required String conversationId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw 'No signed-in user found.';
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await messagesRef(conversationId).add({
      'conversationId': conversationId,
      'senderId': user.uid,
      'senderEmail': user.email ?? '',
      'senderRole': 'user',
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await conversationsRef.doc(conversationId).set({
      'lastMessage': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderRole': 'user',
      'unreadByAdmin': true,
      'unreadByUser': false,
      'status': 'open',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendAdminMessage({
    required String conversationId,
    required String text,
    required String adminUid,
    required String adminEmail,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await messagesRef(conversationId).add({
      'conversationId': conversationId,
      'senderId': adminUid,
      'senderEmail': adminEmail,
      'senderRole': 'admin',
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await conversationsRef.doc(conversationId).set({
      'lastMessage': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderRole': 'admin',
      'unreadByAdmin': false,
      'unreadByUser': true,
      'status': 'open',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateConversationStatus({
    required String conversationId,
    required String status,
  }) async {
    await conversationsRef.doc(conversationId).set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markReadByUser(String conversationId) async {
    await conversationsRef.doc(conversationId).set({
      'unreadByUser': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markReadByAdmin(String conversationId) async {
    await conversationsRef.doc(conversationId).set({
      'unreadByAdmin': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
