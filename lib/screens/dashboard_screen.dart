import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/notification_service.dart';

class UnifiedDashboardScreen extends StatefulWidget {
  const UnifiedDashboardScreen({super.key});

  @override
  State<UnifiedDashboardScreen> createState() => _UnifiedDashboardScreenState();
}

class _UnifiedDashboardScreenState extends State<UnifiedDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _useDemoMode = false;

  // Mock data for immediate UI testing without active backend/Firebase keys
  final List<Map<String, dynamic>> _mockPRs = [
    {
      'repo': 'NeelBelsare/flutter',
      'pr_number': '42',
      'title': 'feat: Vite frontend asset optimization & bundle chunking',
      'author': 'neel-dev',
      'status': 'pending_review',
      'analysis':
          'AI Code Review (GPT-4o):\n✓ Syntax verified.\n⚠️ Bottleneck: Unused lodash bundle imported at top level.\n💡 Proposed Patch:\n- import _ from "lodash";\n+ import debounce from "lodash/debounce";',
    },
    {
      'repo': 'NeelBelsare/flutter',
      'pr_number': '39',
      'title': 'fix: Flask async webhook deadlock on task injection',
      'author': 'collaborator-1',
      'status': 'merged',
      'analysis':
          'AI Code Review (GPT-4o):\n✓ Thread safe lock applied.\n✓ Solved concurrency race condition.',
    },
    {
      'repo': 'devops-infra/raspberry-cluster',
      'pr_number': '18',
      'title': 'chore: Upgrade IoT telemetry daemon to Python 3.12',
      'author': 'alex-iot',
      'status': 'closed',
      'analysis':
          'AI Code Review (GPT-4o):\n❌ Incompatible SPI library on target firmware. PR recommended for closure.',
    },
  ];

  final List<Map<String, dynamic>> _mockTasks = [
    {
      'task_name': '[P0] Database connection pool leak under heavy load',
      'source': 'github_issue',
      'repo': 'NeelBelsare/flutter',
      'category': 'Bug',
      'estimated_hours': 2,
      'status': 'in_progress',
      'deadline': 'Today 6:00 PM',
    },
    {
      'task_name': 'Order replacement temperature sensors for IoT rig',
      'source': 'telegram',
      'context': 'Transcribed from voice note via Whisper-1',
      'deadline': 'Tomorrow 10:00 AM',
      'status': 'pending',
    },
    {
      'task_name': '[P1] Add rate limiting middleware to Vite reverse proxy',
      'source': 'github_issue',
      'repo': 'devops-infra/gateway',
      'category': 'Feature',
      'estimated_hours': 3,
      'status': 'queued',
      'deadline': 'End of Week',
    },
    {
      'task_name': 'Review Raspberry Pi boot script stdout logs',
      'source': 'telegram',
      'context': 'Text command /task from Telegram bot',
      'deadline': 'Flexible',
      'status': 'completed',
    },
  ];

  final List<Map<String, dynamic>> _mockLogs = [
    {
      'command': 'restart_pi',
      'exit_code': 0,
      'stdout':
          'systemd[1]: Stopping IoT Telemetry Daemon...\nsystemd[1]: Starting IoT Telemetry Daemon...\nsystemd[1]: Started IoT Telemetry Daemon on raspberrypi.local.\nStatus: Active (running) - PID 1420',
      'stderr': '',
    },
    {
      'command': 'deploy_vite',
      'exit_code': 0,
      'stdout':
          'vite v5.2.0 building for production...\n✓ 48 modules transformed.\ndist/index.html 0.48 kB │ gzip: 0.31 kB\ndist/assets/index-C7.js 142.12 kB │ gzip: 45.20 kB\n✓ Built in 410ms.',
      'stderr': '',
    },
    {
      'command': 'restart_flask',
      'exit_code': 0,
      'stdout': 'flask_devops.service reloaded successfully. Workers active: 4',
      'stderr': '',
    },
  ];

  bool get _isFirebaseReady => Firebase.apps.isNotEmpty && !_useDemoMode;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Sends an immediate actionable notification with custom sound to test the alert on device
  Future<void> _sendTestActionableNotification() async {
    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();

    const AndroidNotificationAction approveAction = AndroidNotificationAction(
      NotificationService.actionIdApprove,
      'Approve & Merge',
      showsUserInterface: true,
      cancelNotification: true,
    );

    const AndroidNotificationAction denyAction = AndroidNotificationAction(
      NotificationService.actionIdDeny,
      'Deny / Close',
      showsUserInterface: false,
      cancelNotification: true,
    );

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'devops_action_channel_v2',
      'DevOps Actions & PR Alerts',
      channelDescription: 'Actionable PR merges, denials, and pipeline alerts with sound',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('notification_sound'),
      enableVibration: true,
      actions: const [approveAction, denyAction],
    );

    final NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await localNotifications.show(
      id: 999,
      title: '⚡ PR Review: #42 in NeelBelsare/flutter',
      body: 'AI detected 1 bottleneck in Vite build. Approve patch or deny?',
      notificationDetails: notificationDetails,
      payload: '{"repo": "NeelBelsare/flutter", "pr_number": "42"}',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Actionable notification sent! Check your notification shade.'),
          backgroundColor: Colors.cyan,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DevOps & Manager Hub',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_rounded),
            tooltip: 'Trigger Test Actionable Notification',
            onPressed: _sendTestActionableNotification,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'toggle_mode') {
                setState(() {
                  _useDemoMode = !_useDemoMode;
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_mode',
                child: Row(
                  children: [
                    Icon(
                      _useDemoMode ? Icons.cloud_outlined : Icons.preview_rounded,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(_useDemoMode ? 'Switch to Live Mode' : 'Switch to Demo Preview'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.merge_type_rounded), text: 'GitHub PRs'),
            Tab(icon: Icon(Icons.task_alt_rounded), text: 'Task Queue'),
            Tab(icon: Icon(Icons.terminal_rounded), text: 'Pipeline Logs'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Mode Indicator Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _isFirebaseReady
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.blueGrey.withValues(alpha: 0.2),
            child: Row(
              children: [
                Icon(
                  _isFirebaseReady ? Icons.cloud_done_rounded : Icons.visibility_rounded,
                  size: 18,
                  color: _isFirebaseReady ? Colors.green : Colors.cyan,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isFirebaseReady
                        ? 'Live Firestore connected'
                        : 'Preview Mode (Interactive Mock Data)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isFirebaseReady ? Colors.green : Colors.cyanAccent,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _sendTestActionableNotification,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Test Notification', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _isFirebaseReady ? _buildLivePRList() : _buildMockPRList(),
                _isFirebaseReady ? _buildLiveTaskQueueList() : _buildMockTaskQueueList(),
                _isFirebaseReady ? _buildLivePipelineLogsList() : _buildMockPipelineLogsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Tab 1: GitHub PR Reviews
  // -------------------------------------------------------------
  Widget _buildMockPRList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _mockPRs.length,
      itemBuilder: (context, index) {
        final pr = _mockPRs[index];
        return _buildPRCard(
          repo: pr['repo'],
          prNumber: pr['pr_number'],
          title: pr['title'],
          status: pr['status'],
          analysis: pr['analysis'],
          onApprove: () {
            setState(() {
              pr['status'] = 'merged';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Approved & Merged PR #${pr['pr_number']}!')),
            );
          },
          onDeny: () {
            setState(() {
              pr['status'] = 'closed';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Closed PR #${pr['pr_number']}')),
            );
          },
        );
      },
    );
  }

  Widget _buildLivePRList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('github_prs')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No active PR reviews'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final String repo = data['repo'] ?? '';
            final String prNumber = data['pr_number']?.toString() ?? '';
            final String status = data['status'] ?? 'pending';

            return _buildPRCard(
              repo: repo,
              prNumber: prNumber,
              title: data['title'] ?? 'Pull Request',
              status: status,
              analysis: data['analysis'] ?? 'No analysis available',
              onApprove: () {
                NotificationService.instance
                    .triggerPrDecision(repo, prNumber, 'approve_merge');
              },
              onDeny: () {
                NotificationService.instance
                    .triggerPrDecision(repo, prNumber, 'deny_close');
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPRCard({
    required String repo,
    required String prNumber,
    required String title,
    required String status,
    required String analysis,
    required VoidCallback onApprove,
    required VoidCallback onDeny,
  }) {
    Color statusColor = Colors.amber;
    IconData statusIcon = Icons.hourglass_top_rounded;
    if (status == 'merged') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'closed') {
      statusColor = Colors.redAccent;
      statusIcon = Icons.cancel_rounded;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        leading: Icon(statusIcon, color: statusColor, size: 28),
        title: Text(
          '#$prNumber: $title',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          'Repo: $repo • Status: ${status.toUpperCase()}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Root-Cause & Code Review:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    analysis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                if (status == 'pending_review' || status == 'pending')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onDeny,
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Deny / Close'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.merge_type, size: 16),
                        label: const Text('Approve & Merge'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Tab 2: Task Queue
  // -------------------------------------------------------------
  Widget _buildMockTaskQueueList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _mockTasks.length,
      itemBuilder: (context, index) {
        final task = _mockTasks[index];
        return _buildTaskTile(
          taskName: task['task_name'],
          source: task['source'],
          deadline: task['deadline'],
          context: task['context'],
          status: task['status'],
        );
      },
    );
  }

  Widget _buildLiveTaskQueueList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('task_queue')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('Task queue empty'));

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildTaskTile(
              taskName: data['task_name'] ?? 'Untitled Task',
              source: data['source'] ?? 'generic',
              deadline: data['deadline'] ?? 'Flexible',
              context: data['context'],
              status: data['status'] ?? 'pending',
            );
          },
        );
      },
    );
  }

  Widget _buildTaskTile({
    required String taskName,
    required String source,
    required String deadline,
    String? context,
    required String status,
  }) {
    final bool isTelegram = source == 'telegram';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isTelegram
              ? Colors.lightBlue.withValues(alpha: 0.25)
              : Colors.orange.withValues(alpha: 0.25),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isTelegram
              ? Colors.lightBlue.withValues(alpha: 0.2)
              : Colors.orange.withValues(alpha: 0.2),
          child: Icon(
            isTelegram ? Icons.send_rounded : Icons.bug_report_rounded,
            color: isTelegram ? Colors.lightBlue : Colors.orange,
            size: 20,
          ),
        ),
        title: Text(taskName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Deadline: $deadline',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            if (context != null)
              Text(
                context,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
          ],
        ),
        trailing: Chip(
          label: Text(
            status,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          backgroundColor: status == 'completed'
              ? Colors.green.withValues(alpha: 0.2)
              : status == 'in_progress'
                  ? Colors.blue.withValues(alpha: 0.2)
                  : Colors.amber.withValues(alpha: 0.2),
          side: BorderSide.none,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Tab 3: Remote Pipeline Execution Logs
  // -------------------------------------------------------------
  Widget _buildMockPipelineLogsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _mockLogs.length,
      itemBuilder: (context, index) {
        final log = _mockLogs[index];
        return _buildLogCard(
          command: log['command'],
          exitCode: log['exit_code'],
          stdout: log['stdout'],
          stderr: log['stderr'],
        );
      },
    );
  }

  Widget _buildLivePipelineLogsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('execution_logs')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No execution logs recorded'));

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildLogCard(
              command: data['command'] ?? 'Unknown',
              exitCode: data['exit_code'] ?? 0,
              stdout: data['stdout'] ?? '',
              stderr: data['stderr'] ?? '',
            );
          },
        );
      },
    );
  }

  Widget _buildLogCard({
    required String command,
    required int exitCode,
    required String stdout,
    required String stderr,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: const Color(0xFF14171A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: exitCode == 0 ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  exitCode == 0 ? Icons.check_circle_outline : Icons.error_outline,
                  color: exitCode == 0 ? Colors.green : Colors.redAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Target: $command',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: exitCode == 0 ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'exit: $exitCode',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: exitCode == 0 ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 16),
            Text(
              stdout.isNotEmpty ? stdout : (stderr.isNotEmpty ? stderr : 'No output captured'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFFB0BEC5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
