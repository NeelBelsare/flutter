import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';

class UnifiedDashboardScreen extends StatefulWidget {
  const UnifiedDashboardScreen({super.key});

  @override
  State<UnifiedDashboardScreen> createState() => _UnifiedDashboardScreenState();
}

class _UnifiedDashboardScreenState extends State<UnifiedDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DevOps & Manager Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.merge_type), text: 'GitHub PRs'),
            Tab(icon: Icon(Icons.task_alt), text: 'Task Queue'),
            Tab(icon: Icon(Icons.terminal), text: 'Pipeline Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPRList(),
          _buildTaskQueueList(),
          _buildPipelineLogsList(),
        ],
      ),
    );
  }

  Widget _buildPRList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('github_prs')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Database Connection: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No active PR reviews'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final String repo = data['repo'] ?? '';
            final String prNumber = data['pr_number']?.toString() ?? '';
            final String status = data['status'] ?? 'pending';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ExpansionTile(
                leading: Icon(
                  status == 'merged'
                      ? Icons.check_circle
                      : status == 'closed'
                          ? Icons.cancel
                          : Icons.pending,
                  color: status == 'merged' ? Colors.green : Colors.amber,
                ),
                title: Text('#$prNumber: ${data['title'] ?? 'Pull Request'}'),
                subtitle: Text('Repo: $repo | Status: $status'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Code Review:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(data['analysis'] ?? 'No analysis available'),
                        const SizedBox(height: 12),
                        if (status == 'pending_review')
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () {
                                  NotificationService.instance.triggerPrDecision(
                                    repo,
                                    prNumber,
                                    'deny_close',
                                  );
                                },
                                child: const Text('Deny / Close'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  NotificationService.instance.triggerPrDecision(
                                    repo,
                                    prNumber,
                                    'approve_merge',
                                  );
                                },
                                child: const Text('Approve & Merge'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTaskQueueList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('task_queue')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Database Connection: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Task queue empty'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final String source = data['source'] ?? 'generic';

            return ListTile(
              leading: Icon(
                source == 'telegram' ? Icons.telegram : Icons.bug_report,
                color: source == 'telegram' ? Colors.lightBlue : Colors.orange,
              ),
              title: Text(data['task_name'] ?? 'Untitled Task'),
              subtitle: Text(
                'Source: $source | Deadline: ${data['deadline'] ?? 'Flexible'}',
              ),
              trailing: Chip(
                label: Text(data['status'] ?? 'pending'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPipelineLogsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('execution_logs')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Database Connection: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No execution logs recorded'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final int exitCode = data['exit_code'] ?? 0;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.black45,
              child: ListTile(
                title: Text(
                  'Target: ${data['command']}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Exit Code: $exitCode'),
                    const SizedBox(height: 4),
                    Text(
                      data['stdout'] != null &&
                              (data['stdout'] as String).isNotEmpty
                          ? data['stdout']
                          : data['stderr'] ?? 'No output',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
