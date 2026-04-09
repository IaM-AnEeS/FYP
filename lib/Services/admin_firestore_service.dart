import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'detection_service.dart';

class AdminFirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get usersRef =>
      _db.collection('users');

  CollectionReference<Map<String, dynamic>> get adminUsersRef =>
      _db.collection('admin_users');

  CollectionReference<Map<String, dynamic>> get alertsRef =>
      _db.collection('alerts');

  CollectionReference<Map<String, dynamic>> get ticketsRef =>
      _db.collection('support_tickets');

  CollectionReference<Map<String, dynamic>> get announcementsRef =>
      _db.collection('announcements');

  CollectionReference<Map<String, dynamic>> get rolesRef => _db.collection('roles');

  CollectionReference<Map<String, dynamic>> get auditLogsRef =>
      _db.collection('audit_logs');

  CollectionReference<Map<String, dynamic>> get adminEventsRef =>
      _db.collection('admin_events');

  CollectionReference<Map<String, dynamic>> get detectionLabelsRef =>
      _db.collection('detection_labels');

    CollectionReference<Map<String, dynamic>> get frameDetectionsRef =>
      _db.collection('frame_detections');

      CollectionReference<Map<String, dynamic>> get userActivityDailyRef =>
        _db.collection('user_activity_daily');

      CollectionReference<Map<String, dynamic>> get detectionSessionsRef =>
        _db.collection('detection_sessions');

      CollectionReference<Map<String, dynamic>> get supportConversationsRef =>
        _db.collection('support_conversations');

  DocumentReference<Map<String, dynamic>> get overviewDoc =>
      _db.collection('admin_metrics').doc('overview');

  DocumentReference<Map<String, dynamic>> get backendConfigDoc =>
      _db.collection('admin_config').doc('backend');

  DocumentReference<Map<String, dynamic>> get featureFlagsDoc =>
      _db.collection('admin_config').doc('feature_flags');

  DocumentReference<Map<String, dynamic>> get systemHealthDoc =>
      _db.collection('system_health').doc('current');

  Future<bool> verifyOrBootstrapAdmin(User user) async {
    final adminDoc = await adminUsersRef.doc(user.uid).get();

    if (adminDoc.exists) {
      final data = adminDoc.data() ?? <String, dynamic>{};
      return data['isActive'] != false;
    }

    final existingAdmins = await adminUsersRef.limit(1).get();
    if (existingAdmins.docs.isNotEmpty) {
      return false;
    }

    // If no admin exists yet, bootstrap the first admin account.
    await adminUsersRef.doc(user.uid).set({
      'email': user.email ?? '',
      'displayName': user.displayName ?? _nameFromEmail(user.email),
      'role': 'super_admin',
      'isActive': true,
      'mfaEnabled': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });

    await writeAuditLog(
      adminUid: user.uid,
      module: 'auth',
      action: 'bootstrap_admin',
      message: 'Bootstrapped first admin account',
      targetId: user.uid,
    );

    return true;
  }

  Future<void> ensureAdminDefaults(User user) async {
    await adminUsersRef.doc(user.uid).set({
      'email': user.email ?? '',
      'displayName': user.displayName ?? _nameFromEmail(user.email),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
      'isActive': true,
    }, SetOptions(merge: true));

    final overviewSnapshot = await overviewDoc.get();
    if (!overviewSnapshot.exists) {
      await overviewDoc.set(defaultOverviewMetrics());
    }

    final backendSnapshot = await backendConfigDoc.get();
    if (!backendSnapshot.exists) {
      await backendConfigDoc.set(defaultBackendConfig());
    }

    final featureFlagsSnapshot = await featureFlagsDoc.get();
    if (!featureFlagsSnapshot.exists) {
      await featureFlagsDoc.set(defaultFeatureFlags());
    }

    final healthSnapshot = await systemHealthDoc.get();
    if (!healthSnapshot.exists) {
      await systemHealthDoc.set(defaultSystemHealth());
    }

    final roleSnapshots = await rolesRef.limit(1).get();
    if (roleSnapshots.docs.isEmpty) {
      final batch = _db.batch();

      batch.set(rolesRef.doc('super_admin'), {
        'name': 'super_admin',
        'description': 'Full access to all admin modules',
        'permissions': [
          'users.read',
          'users.write',
          'config.read',
          'config.write',
          'alerts.read',
          'alerts.write',
          'tickets.read',
          'tickets.write',
          'roles.read',
          'roles.write',
          'audit.read',
          'analytics.read',
          'health.read',
          'health.write',
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(rolesRef.doc('ops_admin'), {
        'name': 'ops_admin',
        'description': 'Operations and incident response role',
        'permissions': [
          'alerts.read',
          'alerts.write',
          'tickets.read',
          'tickets.write',
          'config.read',
          'health.read',
          'health.write',
          'analytics.read',
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(rolesRef.doc('support_admin'), {
        'name': 'support_admin',
        'description': 'Support role for users and tickets',
        'permissions': [
          'users.read',
          'tickets.read',
          'tickets.write',
          'alerts.read',
          'audit.read',
        ],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    }
  }

  Future<void> touchAdminLogin(User user) async {
    await adminUsersRef.doc(user.uid).set({
      'email': user.email ?? '',
      'displayName': user.displayName ?? _nameFromEmail(user.email),
      'lastLoginAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: user.uid,
      module: 'auth',
      action: 'admin_login',
      message: 'Admin signed in',
    );
  }

  Future<void> setUserAccountStatus({
    required String userId,
    required String status,
    required String adminUid,
  }) async {
    final userDocRef = usersRef.doc(userId);
    final beforeSnapshot = await userDocRef.get();
    final beforeData = beforeSnapshot.data();

    final normalizedStatus = status.trim().toLowerCase();
    final payload = <String, dynamic>{
      'accountStatus': normalizedStatus,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
      'suspendedBy': normalizedStatus == 'suspended' ? adminUid : null,
      'suspendedAt':
          normalizedStatus == 'suspended' ? FieldValue.serverTimestamp() : null,
      'reactivatedBy': normalizedStatus == 'active' ? adminUid : null,
      'reactivatedAt':
          normalizedStatus == 'active' ? FieldValue.serverTimestamp() : null,
    };

    await userDocRef.set(payload, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'users',
      action: 'set_account_status',
      targetId: userId,
      before: beforeData,
      after: {'accountStatus': normalizedStatus},
      message: 'Updated user account status to $normalizedStatus',
    );
  }

  Future<void> saveBackendConfig({
    required Map<String, dynamic> data,
    required String adminUid,
  }) async {
    final beforeData = (await backendConfigDoc.get()).data();

    await backendConfigDoc.set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'backend_config',
      action: 'save_backend_config',
      targetId: backendConfigDoc.id,
      before: beforeData,
      after: data,
      message: 'Saved backend and model configuration',
    );
  }

  Future<void> saveFeatureFlags({
    required Map<String, dynamic> data,
    required String adminUid,
  }) async {
    final beforeData = (await featureFlagsDoc.get()).data();

    await featureFlagsDoc.set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'feature_flags',
      action: 'save_feature_flags',
      targetId: featureFlagsDoc.id,
      before: beforeData,
      after: data,
      message: 'Saved feature flags and app settings',
    );
  }

  Future<void> saveSystemHealth({
    required Map<String, dynamic> data,
    required String adminUid,
  }) async {
    final beforeData = (await systemHealthDoc.get()).data();

    await systemHealthDoc.set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'system_health',
      action: 'save_system_health',
      targetId: systemHealthDoc.id,
      before: beforeData,
      after: data,
      message: 'Saved system health snapshot',
    );
  }

  Future<void> createAlert({
    required String title,
    required String details,
    required String severity,
    required String mode,
    required String adminUid,
  }) async {
    final alertRef = alertsRef.doc();
    final payload = {
      'title': title,
      'details': details,
      'severity': severity,
      'mode': mode,
      'status': 'open',
      'assignedTo': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': adminUid,
    };

    await alertRef.set(payload);

    await writeAuditLog(
      adminUid: adminUid,
      module: 'alerts',
      action: 'create_alert',
      targetId: alertRef.id,
      after: payload,
      message: 'Created a new alert',
    );
  }

  Future<void> updateAlert({
    required String alertId,
    required Map<String, dynamic> updates,
    required String adminUid,
  }) async {
    final docRef = alertsRef.doc(alertId);
    final beforeData = (await docRef.get()).data();

    await docRef.set({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'alerts',
      action: 'update_alert',
      targetId: alertId,
      before: beforeData,
      after: updates,
      message: 'Updated alert fields',
    );
  }

  Future<void> createTicket({
    required String userId,
    required String userEmail,
    required String category,
    required String priority,
    required String message,
    required String adminUid,
  }) async {
    final ticketRef = ticketsRef.doc();
    final payload = {
      'userId': userId,
      'userEmail': userEmail,
      'category': category,
      'priority': priority,
      'message': message,
      'status': 'open',
      'assignee': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': adminUid,
    };

    await ticketRef.set(payload);

    await writeAuditLog(
      adminUid: adminUid,
      module: 'tickets',
      action: 'create_ticket',
      targetId: ticketRef.id,
      after: payload,
      message: 'Created support ticket',
    );
  }

  Future<void> updateTicket({
    required String ticketId,
    required Map<String, dynamic> updates,
    required String adminUid,
  }) async {
    final docRef = ticketsRef.doc(ticketId);
    final beforeData = (await docRef.get()).data();

    await docRef.set({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'tickets',
      action: 'update_ticket',
      targetId: ticketId,
      before: beforeData,
      after: updates,
      message: 'Updated support ticket',
    );
  }

  Future<void> upsertAnnouncement({
    String? announcementId,
    required String title,
    required String body,
    required bool isActive,
    required DateTime publishAt,
    required String adminUid,
  }) async {
    final isCreate = announcementId == null || announcementId.isEmpty;
    final docRef = isCreate ? announcementsRef.doc() : announcementsRef.doc(announcementId);
    final beforeData = isCreate ? null : (await docRef.get()).data();

    final payload = {
      'title': title,
      'body': body,
      'isActive': isActive,
      'publishAt': Timestamp.fromDate(publishAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
      if (isCreate) 'createdAt': FieldValue.serverTimestamp(),
      if (isCreate) 'createdBy': adminUid,
    };

    await docRef.set(payload, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'announcements',
      action: isCreate ? 'create_announcement' : 'update_announcement',
      targetId: docRef.id,
      before: beforeData,
      after: payload,
      message: isCreate ? 'Created announcement' : 'Updated announcement',
    );
  }

  Future<void> deleteAnnouncement({
    required String announcementId,
    required String adminUid,
  }) async {
    final docRef = announcementsRef.doc(announcementId);
    final beforeData = (await docRef.get()).data();

    await docRef.delete();

    await writeAuditLog(
      adminUid: adminUid,
      module: 'announcements',
      action: 'delete_announcement',
      targetId: announcementId,
      before: beforeData,
      message: 'Deleted announcement',
    );
  }

  Future<void> upsertRole({
    String? roleId,
    required String name,
    required String description,
    required List<String> permissions,
    required String adminUid,
  }) async {
    final id = (roleId == null || roleId.isEmpty)
        ? _slugify(name)
        : roleId;

    final docRef = rolesRef.doc(id);
    final beforeData = (await docRef.get()).data();

    final payload = {
      'name': name,
      'description': description,
      'permissions': permissions,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    };

    await docRef.set(payload, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'roles',
      action: 'upsert_role',
      targetId: id,
      before: beforeData,
      after: payload,
      message: 'Upserted role $name',
    );
  }

  Future<void> deleteRole({
    required String roleId,
    required String adminUid,
  }) async {
    final docRef = rolesRef.doc(roleId);
    final beforeData = (await docRef.get()).data();

    await docRef.delete();

    await writeAuditLog(
      adminUid: adminUid,
      module: 'roles',
      action: 'delete_role',
      targetId: roleId,
      before: beforeData,
      message: 'Deleted role $roleId',
    );
  }

  Future<void> updateAdminRole({
    required String targetAdminUid,
    required String role,
    required String adminUid,
  }) async {
    final docRef = adminUsersRef.doc(targetAdminUid);
    final beforeData = (await docRef.get()).data();

    await docRef.set({
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'admin_users',
      action: 'update_admin_role',
      targetId: targetAdminUid,
      before: beforeData,
      after: {'role': role},
      message: 'Updated admin role to $role',
    );
  }

  Future<void> setAdminActive({
    required String targetAdminUid,
    required bool isActive,
    required String adminUid,
  }) async {
    final docRef = adminUsersRef.doc(targetAdminUid);
    final beforeData = (await docRef.get()).data();

    await docRef.set({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'admin_users',
      action: 'set_admin_active',
      targetId: targetAdminUid,
      before: beforeData,
      after: {'isActive': isActive},
      message: isActive ? 'Activated admin user' : 'Deactivated admin user',
    );
  }

  Future<void> recordDetectionLabelMetric({
    required String mode,
    required String label,
    required int count,
    required String adminUid,
  }) async {
    final key = '${_slugify(mode)}_${_slugify(label)}';
    final docRef = detectionLabelsRef.doc(key);
    final snapshot = await docRef.get();

    final oldCount = (snapshot.data()?['count'] as num?)?.toInt() ?? 0;
    final newCount = oldCount + count;

    await docRef.set({
      'mode': mode.toLowerCase(),
      'label': label,
      'count': newCount,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminUid,
    }, SetOptions(merge: true));

    await writeAuditLog(
      adminUid: adminUid,
      module: 'detection_ops',
      action: 'record_label_metric',
      targetId: key,
      before: {'count': oldCount},
      after: {'count': newCount, 'mode': mode, 'label': label},
      message: 'Recorded detection label metric',
    );
  }

  Future<void> logAdminEvent({
    required String type,
    required String adminUid,
    String? mode,
    num? value,
    Map<String, dynamic>? payload,
  }) async {
    await adminEventsRef.add({
      'type': type,
      'mode': mode,
      'value': value,
      'payload': payload,
      'adminUid': adminUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> writeAuditLog({
    required String adminUid,
    required String module,
    required String action,
    String? targetId,
    String? message,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) async {
    await auditLogsRef.add({
      'adminUid': adminUid,
      'module': module,
      'action': action,
      'targetId': targetId,
      'message': message,
      'before': before,
      'after': after,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Map<String, dynamic> defaultOverviewMetrics() {
    return {
      'dailyActiveUsers': 0,
      'newUsersToday': 0,
      'totalSessionsToday': 0,
      'totalDetectionsToday': 0,
      'indoorRequestsToday': 0,
      'outdoorRequestsToday': 0,
      'successRate': 100.0,
      'timeoutRate': 0.0,
      'avgInferenceMs': 0.0,
      'crashFreeRate': 100.0,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> defaultBackendConfig() {
    return {
      'indoorBaseUrl': kIndoorBackendBaseUrl,
      'outdoorBaseUrl': kOutdoorBackendBaseUrl,
      'predictEndpoint': '/predict',
      'healthEndpoint': '/health',
      'requestTimeoutMs': 8000,
      'indoorModelVersion': 'v1',
      'outdoorModelVersion': 'v1',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> defaultFeatureFlags() {
    return {
      'indoorEnabled': true,
      'outdoorEnabled': true,
      'showDebugPanel': true,
      'captureIntervalMs': 500,
      'minSupportedVersion': '1.0.0',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> defaultSystemHealth() {
    return {
      'firebaseOk': true,
      'indoorApiOk': true,
      'outdoorApiOk': true,
      'dbLatencyMs': 0,
      'queueBacklog': 0,
      'apiErrorSpike': false,
      'notes': '',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  String _nameFromEmail(String? email) {
    if (email == null || email.isEmpty) return 'Admin';
    return email.split('@').first;
  }

  String _slugify(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
