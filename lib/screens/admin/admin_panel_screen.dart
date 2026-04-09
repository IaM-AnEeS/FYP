import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../Services/admin_firestore_service.dart';
import '../../Services/support_chat_service.dart';

enum AdminSection {
  overview,
  users,
  detectionOps,
  support,
}

class _AdminSectionConfig {
  final AdminSection section;
  final String title;
  final IconData icon;

  const _AdminSectionConfig({
    required this.section,
    required this.title,
    required this.icon,
  });
}

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final AdminFirestoreService _adminService = AdminFirestoreService();
  final SupportChatService _supportChatService = SupportChatService();

  final List<_AdminSectionConfig> _sections = const [
    _AdminSectionConfig(
      section: AdminSection.overview,
      title: 'Overview Dashboard',
      icon: Icons.dashboard_outlined,
    ),
    _AdminSectionConfig(
      section: AdminSection.users,
      title: 'User Management',
      icon: Icons.people_outline,
    ),
    _AdminSectionConfig(
      section: AdminSection.detectionOps,
      title: 'Detection Operations',
      icon: Icons.track_changes_outlined,
    ),
    _AdminSectionConfig(
      section: AdminSection.support,
      title: 'Feedback and Tickets',
      icon: Icons.support_agent_outlined,
    ),
  ];

  AdminSection _selectedSection = AdminSection.overview;
  bool _checkingAccess = true;
  String? _accessError;
  User? _adminUser;

  @override
  void initState() {
    super.initState();
    unawaited(_verifyAccess());
  }

  Future<void> _verifyAccess() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _checkingAccess = false;
          _accessError = 'No signed-in account found. Please login first.';
        });
        return;
      }

      final canAccess = await _adminService.verifyOrBootstrapAdmin(user);
      if (!canAccess) {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _checkingAccess = false;
          _accessError = 'This account is not authorized for admin access.';
        });
        return;
      }

      await _adminService.ensureAdminDefaults(user);
      await _adminService.touchAdminLogin(user);

      setState(() {
        _adminUser = user;
        _checkingAccess = false;
        _accessError = null;
      });
    } catch (e) {
      setState(() {
        _checkingAccess = false;
        _accessError = 'Failed to initialize admin panel: $e';
      });
    }
  }

  Future<void> _logoutAdmin() async {
    final uid = _adminUser?.uid;
    if (uid != null) {
      await _adminService.logAdminEvent(
        type: 'admin_logout',
        adminUid: uid,
      );
    }

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_checkingAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Panel')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_accessError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Panel')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 60,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _accessError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/admin-login',
                      (_) => false,
                    );
                  },
                  child: const Text('Go to Admin Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final user = _adminUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Panel')),
        body: const Center(child: Text('Admin user unavailable')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logoutAdmin,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _adminService.adminUsersRef.doc(user.uid).snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() ?? <String, dynamic>{};
                  final role = _stringValue(data['role'], fallback: 'admin');
                  final name = _stringValue(
                    data['displayName'],
                    fallback: _stringValue(user.email, fallback: 'Admin'),
                  );

                  return UserAccountsDrawerHeader(
                    accountName: Text(name),
                    accountEmail: Text(user.email ?? ''),
                    currentAccountPicture: CircleAvatar(
                      backgroundColor: theme.colorScheme.onPrimary,
                      child: Text(
                        name.isEmpty ? 'A' : name.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    otherAccountsPictures: [
                      Chip(
                        label: Text(
                          role,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  );
                },
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _sections.length,
                  itemBuilder: (context, index) {
                    final item = _sections[index];
                    final selected = item.section == _selectedSection;
                    return ListTile(
                      selected: selected,
                      leading: Icon(item.icon),
                      title: Text(item.title),
                      onTap: () {
                        setState(() {
                          _selectedSection = item.section;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: _buildSectionBody(
          adminUid: user.uid,
          adminEmail: user.email ?? '',
        ),
      ),
    );
  }

  Widget _buildSectionBody({
    required String adminUid,
    required String adminEmail,
  }) {
    switch (_selectedSection) {
      case AdminSection.overview:
        return _AdminOverviewSection(adminService: _adminService);
      case AdminSection.users:
        return _AdminUsersSection(
          adminService: _adminService,
          adminUid: adminUid,
        );
      case AdminSection.detectionOps:
        return _AdminDetectionOpsSection(adminService: _adminService);
      case AdminSection.support:
        return _AdminSupportSection(
          supportChatService: _supportChatService,
          adminUid: adminUid,
          adminEmail: adminEmail,
        );
    }
  }
}

class _AdminOverviewSection extends StatelessWidget {
  final AdminFirestoreService adminService;

  const _AdminOverviewSection({required this.adminService});

  @override
  Widget build(BuildContext context) {
    final todayKey = _todayKey(DateTime.now());

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: adminService.usersRef.snapshots(),
      builder: (context, usersSnapshot) {
        final users = usersSnapshot.data?.docs ?? [];
        final totalUsers = users.length;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream:
              adminService.userActivityDailyRef.where('dateKey', isEqualTo: todayKey).snapshots(),
          builder: (context, activitySnapshot) {
            final activityDocs = activitySnapshot.data?.docs ?? [];
            int totalUsageSeconds = 0;
            for (final doc in activityDocs) {
              totalUsageSeconds += _intValue(doc.data()['totalUsageSeconds']);
            }

            final dailyAvgUsagePercent = activityDocs.isEmpty
                ? 0.0
                : ((totalUsageSeconds / activityDocs.length) / 86400.0) * 100.0;
            final normalizedDailyAvgUsagePercent =
                dailyAvgUsagePercent.clamp(0.0, 100.0);

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: adminService.detectionSessionsRef
                  .where('dateKey', isEqualTo: todayKey)
                  .snapshots(),
              builder: (context, sessionsSnapshot) {
                final sessions = sessionsSnapshot.data?.docs ?? [];
                int detectionsToday = 0;
                int successfulSessions = 0;

                for (final doc in sessions) {
                  final data = doc.data();
                  detectionsToday += _intValue(data['detectionsCount']);
                  if (_boolValue(data['isSuccessful'])) {
                    successfulSessions += 1;
                  }
                }

                final successRate = sessions.isEmpty
                    ? 0.0
                    : (successfulSessions / sessions.length) * 100.0;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Overview Dashboard',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Realtime values from Firestore collections for $todayKey',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildResponsiveMetricCards(
                          constraints: constraints,
                          cards: [
                            _MetricCard(
                              title: 'Total Users',
                              value: totalUsers.toString(),
                              icon: Icons.people,
                            ),
                            _MetricCard(
                              title: 'Daily Avg Usage %',
                              value:
                                  '${normalizedDailyAvgUsagePercent.toStringAsFixed(1)}%',
                              icon: Icons.access_time,
                            ),
                            _MetricCard(
                              title: 'Detections Today',
                              value: detectionsToday.toString(),
                              icon: Icons.visibility,
                            ),
                            _MetricCard(
                              title: 'Success Rate',
                              value: '${successRate.toStringAsFixed(1)}%',
                              icon: Icons.check_circle_outline,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today Summary',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text('Active users today: ${activityDocs.length}'),
                            Text('Detection sessions today: ${sessions.length}'),
                            Text('Successful sessions today: $successfulSessions'),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AdminUsersSection extends StatefulWidget {
  final AdminFirestoreService adminService;
  final String adminUid;

  const _AdminUsersSection({
    required this.adminService,
    required this.adminUid,
  });

  @override
  State<_AdminUsersSection> createState() => _AdminUsersSectionState();
}

class _AdminUsersSectionState extends State<_AdminUsersSection> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _setStatus(String userId, String status) async {
    await widget.adminService.setUserAccountStatus(
      userId: userId,
      status: status,
      adminUid: widget.adminUid,
    );

    if (!mounted) return;
    _showSnack(context, 'User status updated to $status');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search users by name or email',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.adminService.usersRef.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              final query = _searchController.text.trim().toLowerCase();

              final filtered = docs.where((doc) {
                final data = doc.data();
                final name = _stringValue(data['name']).toLowerCase();
                final email = _stringValue(data['email']).toLowerCase();
                if (query.isEmpty) return true;
                return name.contains(query) || email.contains(query);
              }).toList();

              filtered.sort((a, b) {
                final aDate = _toDateTime(a.data()['createdAt']) ?? DateTime(1970);
                final bDate = _toDateTime(b.data()['createdAt']) ?? DateTime(1970);
                return bDate.compareTo(aDate);
              });

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('No users found for the current filter'),
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final doc = filtered[index];
                  final data = doc.data();
                  final name = _stringValue(data['name'], fallback: 'Unknown');
                  final email = _stringValue(data['email'], fallback: '-');
                  final status = _stringValue(
                    data['accountStatus'],
                    fallback: 'active',
                  ).toLowerCase();
                  final isSuspended = status == 'suspended';

                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        name.isEmpty ? 'U' : name.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(name),
                    subtitle: Text(
                      '$email\nStatus: ${isSuspended ? 'suspended' : 'active'}\nCreated: ${_formatDateTime(data['createdAt'])}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'view') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AdminUserDetailScreen(
                                userId: doc.id,
                                adminUid: widget.adminUid,
                                adminService: widget.adminService,
                              ),
                            ),
                          );
                          return;
                        }

                        if (value == 'activate') {
                          await _setStatus(doc.id, 'active');
                        }
                        if (value == 'suspend') {
                          await _setStatus(doc.id, 'suspended');
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('View details'),
                        ),
                        const PopupMenuItem(
                          value: 'activate',
                          child: Text('Reactivate user'),
                        ),
                        const PopupMenuItem(
                          value: 'suspend',
                          child: Text('Suspend user'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class AdminUserDetailScreen extends StatelessWidget {
  final String userId;
  final String adminUid;
  final AdminFirestoreService adminService;

  const AdminUserDetailScreen({
    super.key,
    required this.userId,
    required this.adminUid,
    required this.adminService,
  });

  Future<void> _setStatus(BuildContext context, String status) async {
    await adminService.setUserAccountStatus(
      userId: userId,
      status: status,
      adminUid: adminUid,
    );

    if (!context.mounted) return;
    _showSnack(context, 'User updated to $status');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Detail')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: adminService.usersRef.doc(userId).snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnapshot.data?.data();
          if (userData == null) {
            return const Center(child: Text('User not found'));
          }

          final name = _stringValue(userData['name'], fallback: 'Unknown');
          final email = _stringValue(userData['email'], fallback: '-');
          final status = _stringValue(userData['accountStatus'], fallback: 'active');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('User ID: $userId'),
                      Text('Email: $email'),
                      Text('Status: $status'),
                      Text('Created: ${_formatDateTime(userData['createdAt'])}'),
                      Text('Updated: ${_formatDateTime(userData['updatedAt'])}'),
                      if (_toDateTime(userData['suspendedAt']) != null)
                        Text('Suspended At: ${_formatDateTime(userData['suspendedAt'])}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: () => _setStatus(context, 'active'),
                            child: const Text('Reactivate'),
                          ),
                          OutlinedButton(
                            onPressed: () => _setStatus(context, 'suspended'),
                            child: const Text('Suspend'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Support Conversation Snapshot',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: adminService.supportConversationsRef.doc(userId).snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data();
                  if (data == null) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No conversation found for this user yet.'),
                      ),
                    );
                  }

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status: ${_stringValue(data['status'], fallback: 'open')}'),
                          const SizedBox(height: 6),
                          Text('Last message: ${_stringValue(data['lastMessage'])}'),
                          Text('Last updated: ${_formatDateTime(data['lastMessageAt'])}'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminDetectionOpsSection extends StatelessWidget {
  final AdminFirestoreService adminService;

  const _AdminDetectionOpsSection({required this.adminService});

  @override
  Widget build(BuildContext context) {
    final todayKey = _todayKey(DateTime.now());

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: adminService.detectionSessionsRef
          .where('dateKey', isEqualTo: todayKey)
          .snapshots(),
      builder: (context, sessionsSnapshot) {
        final sessions = sessionsSnapshot.data?.docs ?? [];

        int indoorSessions = 0;
        int outdoorSessions = 0;
        int totalDetections = 0;
        int successfulSessions = 0;
        double totalInferenceMs = 0;

        for (final doc in sessions) {
          final data = doc.data();
          final mode = _stringValue(data['mode']).toLowerCase();
          if (mode == 'indoor') {
            indoorSessions += 1;
          } else if (mode == 'outdoor') {
            outdoorSessions += 1;
          }

          totalDetections += _intValue(data['detectionsCount']);
          totalInferenceMs += _doubleValue(data['averageInferenceMs']);
          if (_boolValue(data['isSuccessful'])) {
            successfulSessions += 1;
          }
        }

        final avgInferenceMs = sessions.isEmpty ? 0.0 : totalInferenceMs / sessions.length;
        final successRate = sessions.isEmpty ? 0.0 : (successfulSessions / sessions.length) * 100;

        final sortedSessions = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(sessions)
          ..sort((a, b) {
            final aDate = _toDateTime(a.data()['startedAt']) ?? DateTime(1970);
            final bDate = _toDateTime(b.data()['startedAt']) ?? DateTime(1970);
            return bDate.compareTo(aDate);
          });

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: adminService.frameDetectionsRef
              .orderBy('createdAt', descending: true)
              .limit(60)
              .snapshots(),
          builder: (context, framesSnapshot) {
            final frameDocs = framesSnapshot.data?.docs ?? [];
            final Map<String, int> labelCounts = <String, int>{};

            for (final doc in frameDocs) {
              final label = _stringValue(doc.data()['frameName'], fallback: 'unknown');
              labelCounts[label] = (labelCounts[label] ?? 0) + 1;
            }

            final topLabels = labelCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Detection Operations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Live analytics from detection_sessions and frame_detections',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return _buildResponsiveMetricCards(
                      constraints: constraints,
                      cards: [
                        _MetricCard(
                          title: 'Sessions Today',
                          value: sessions.length.toString(),
                          icon: Icons.play_circle_outline,
                        ),
                        _MetricCard(
                          title: 'Detections Today',
                          value: totalDetections.toString(),
                          icon: Icons.visibility,
                        ),
                        _MetricCard(
                          title: 'Success Rate',
                          value: '${successRate.toStringAsFixed(1)}%',
                          icon: Icons.check_circle_outline,
                        ),
                        _MetricCard(
                          title: 'Avg Inference',
                          value: '${avgInferenceMs.toStringAsFixed(1)} ms',
                          icon: Icons.speed,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mode Distribution',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('Indoor sessions: $indoorSessions'),
                        Text('Outdoor sessions: $outdoorSessions'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Top Detected Labels (Recent Frames)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (topLabels.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No frame logs available yet.'),
                    ),
                  )
                else
                  ...topLabels.take(10).map((entry) {
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.label_outline),
                        title: Text(entry.key),
                        trailing: Text(
                          entry.value.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                Text(
                  'Recent Detection Sessions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (sortedSessions.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No detection sessions found for today.'),
                    ),
                  )
                else
                  ...sortedSessions.take(20).map((doc) {
                    final data = doc.data();
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          _stringValue(data['mode']).toLowerCase() == 'indoor'
                              ? Icons.home_work_outlined
                              : Icons.navigation_outlined,
                        ),
                        title: Text(
                          '${_stringValue(data['userEmail'], fallback: '-')}\nMode: ${_stringValue(data['mode'])}',
                        ),
                        subtitle: Text(
                          'Detections: ${_intValue(data['detectionsCount'])} | Duration: ${_intValue(data['durationSeconds'])} sec\nStarted: ${_formatDateTime(data['startedAt'])}',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }
}

class _AdminSupportSection extends StatefulWidget {
  final SupportChatService supportChatService;
  final String adminUid;
  final String adminEmail;

  const _AdminSupportSection({
    required this.supportChatService,
    required this.adminUid,
    required this.adminEmail,
  });

  @override
  State<_AdminSupportSection> createState() => _AdminSupportSectionState();
}

class _AdminSupportSectionState extends State<_AdminSupportSection> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _threadScrollController = ScrollController();

  String? _selectedConversationId;
  bool _sendingReply = false;

  @override
  void dispose() {
    _messageController.dispose();
    _threadScrollController.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final conversationId = _selectedConversationId;
    final text = _messageController.text.trim();

    if (conversationId == null || text.isEmpty || _sendingReply) return;

    setState(() {
      _sendingReply = true;
      _messageController.clear();
    });

    try {
      await widget.supportChatService.sendAdminMessage(
        conversationId: conversationId,
        text: text,
        adminUid: widget.adminUid,
        adminEmail: widget.adminEmail,
      );
      await widget.supportChatService.markReadByAdmin(conversationId);
      _scrollThreadToBottom();
    } catch (e) {
      if (!mounted) return;
      _showSnack(context, 'Failed to send reply: $e');
    } finally {
      if (mounted) {
        setState(() {
          _sendingReply = false;
        });
      }
    }
  }

  void _scrollThreadToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_threadScrollController.hasClients) return;
      _threadScrollController.animateTo(
        _threadScrollController.position.maxScrollExtent + 220,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.supportChatService.watchConversations(),
      builder: (context, snapshot) {
        final conversations = snapshot.data?.docs ?? [];

        if (conversations.isNotEmpty && _selectedConversationId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || conversations.isEmpty) return;
            setState(() {
              _selectedConversationId = conversations.first.id;
            });
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 920;
            final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

            if (isWide) {
              return Row(
                children: [
                  SizedBox(
                    width: 340,
                    child: _buildConversationList(conversations),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _buildConversationThread(conversations),
                  ),
                ],
              );
            }

            if (keyboardOpen) {
              return Column(
                children: [
                  Expanded(
                    child: _buildConversationThread(
                      conversations,
                      compact: true,
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                SizedBox(
                  height: 260,
                  child: _buildConversationList(conversations),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _buildConversationThread(
                    conversations,
                    compact: false,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildConversationList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> conversations,
  ) {
    if (conversations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No user conversations yet.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(
            'Feedback and Tickets',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            'Unified realtime support conversations',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final doc = conversations[index];
              final data = doc.data();
              final selected = doc.id == _selectedConversationId;
              final unreadByAdmin = _boolValue(data['unreadByAdmin']);
              final status = _stringValue(data['status'], fallback: 'open');

              return ListTile(
                selected: selected,
                onTap: () {
                  setState(() {
                    _selectedConversationId = doc.id;
                  });
                  unawaited(widget.supportChatService.markReadByAdmin(doc.id));
                },
                leading: CircleAvatar(
                  child: Text(
                    _stringValue(data['userEmail'], fallback: 'U')
                        .characters
                        .first
                        .toUpperCase(),
                  ),
                ),
                title: Text(_stringValue(data['userEmail'], fallback: doc.id)),
                subtitle: Text(
                  '${_stringValue(data['lastMessage'])}\n${_formatDateTime(data['lastMessageAt'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (unreadByAdmin)
                      const Icon(Icons.mark_email_unread_outlined, size: 18),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        color: status == 'resolved'
                            ? Colors.green
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConversationThread(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> conversations,
    {bool compact = false}
  ) {
    final selectedId = _selectedConversationId;
    if (selectedId == null) {
      return const Center(
        child: Text('Select a conversation to view messages.'),
      );
    }

    final selectedConversation = conversations.where((doc) => doc.id == selectedId);
    if (selectedConversation.isEmpty) {
      return const Center(
        child: Text('Selected conversation is no longer available.'),
      );
    }

    final conversationData = selectedConversation.first.data();
    final status = _stringValue(conversationData['status'], fallback: 'open');

    return Column(
      children: [
        if (!compact)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stringValue(conversationData['userEmail'], fallback: selectedId),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('User ID: ${_stringValue(conversationData['userId'], fallback: selectedId)}'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      await widget.supportChatService.updateConversationStatus(
                        conversationId: selectedId,
                        status: value,
                      );
                      if (!mounted) return;
                      _showSnack(context, 'Conversation status updated to $value');
                    },
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.supportChatService.watchMessages(selectedId),
            builder: (context, snapshot) {
              final messages = snapshot.data?.docs ?? [];

              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(widget.supportChatService.markReadByAdmin(selectedId));
              });

              if (messages.isEmpty) {
                return const Center(
                  child: Text('No messages yet for this conversation.'),
                );
              }

              return ListView.builder(
                controller: _threadScrollController,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final data = messages[index].data();
                  final senderRole = _stringValue(data['senderRole'], fallback: 'user').toLowerCase();
                  final isAdmin = senderRole == 'admin';
                  final text = _stringValue(data['text']);

                  return Align(
                    alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isAdmin
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(isAdmin ? 12 : 0),
                          bottomRight: Radius.circular(isAdmin ? 0 : 12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text,
                            style: TextStyle(
                              color: isAdmin
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatDateTime(data['createdAt']),
                            style: TextStyle(
                              fontSize: 11,
                              color: isAdmin
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimary
                                      .withValues(alpha: 0.75)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.7),
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
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, compact ? 6 : 8, 12, compact ? 8 : 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendReply(),
                    decoration: const InputDecoration(
                      hintText: 'Write an admin reply...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sendingReply ? null : _sendReply,
                  icon: _sendingReply
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Reply'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildResponsiveMetricCards({
  required BoxConstraints constraints,
  required List<Widget> cards,
}) {
  final width = constraints.maxWidth;

  if (width < 560) {
    return Column(
      children: cards
          .map(
            (card) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(width: double.infinity, child: card),
            ),
          )
          .toList(),
    );
  }

  final crossAxisCount = width >= 900 ? 4 : 2;

  return GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: cards.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      mainAxisExtent: 160,
    ),
    itemBuilder: (context, index) => cards[index],
  );
}

String _stringValue(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

int _intValue(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

double _doubleValue(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

bool _boolValue(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return fallback;
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _formatDateTime(dynamic value) {
  final date = _toDateTime(value);
  if (date == null) return '-';

  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');

  return '$y-$m-$d $hh:$mm';
}

String _todayKey(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y$m$d';
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
