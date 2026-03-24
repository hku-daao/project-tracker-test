import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../config/admin_config.dart';
import '../../services/backend_api.dart';

/// System admin: users, teams, team members, subordinates. Only [AdminConfig.systemAdminEmail].
class SystemAdminScreen extends StatefulWidget {
  const SystemAdminScreen({super.key});

  @override
  State<SystemAdminScreen> createState() => _SystemAdminScreenState();
}

class _SystemAdminScreenState extends State<SystemAdminScreen> {
  Map<String, dynamic>? _snapshot;
  bool _loading = true;
  String? _error;
  String _userSearchQuery = '';
  final _userSearchController = TextEditingController();

  final _firebaseUid = TextEditingController();
  final _userEmail = TextEditingController();
  final _displayName = TextEditingController();
  final _staffAppId = TextEditingController();
  String _roleAppId = 'staff';
  final _teamName = TextEditingController();
  final _teamAppId = TextEditingController();
  final _tmTeam = TextEditingController();
  final _tmStaff = TextEditingController();
  String _tmRole = 'member';
  final _supStaff = TextEditingController();
  final _subStaff = TextEditingController();
  final _deleteAppUserId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  Future<void> _checkAndLoad() async {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (email != AdminConfig.systemAdminEmail.toLowerCase()) {
      setState(() {
        _loading = false;
        _error = 'Access denied.';
      });
      return;
    }
    await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    final snap = await BackendApi().getAdminSnapshot(token);
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _loading = false;
      if (snap == null) _error = 'Failed to load snapshot (403 or network).';
    });
  }

  @override
  void dispose() {
    _firebaseUid.dispose();
    _userEmail.dispose();
    _displayName.dispose();
    _staffAppId.dispose();
    _teamName.dispose();
    _teamAppId.dispose();
    _tmTeam.dispose();
    _tmStaff.dispose();
    _supStaff.dispose();
    _subStaff.dispose();
    _deleteAppUserId.dispose();
    _userSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (email != AdminConfig.systemAdminEmail.toLowerCase()) {
      return Scaffold(
        appBar: AppBar(title: const Text('System Admin')),
        body: const Center(child: Text('Access denied.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Users & Roles', icon: Icon(Icons.people)),
                          Tab(text: 'Teams & Members', icon: Icon(Icons.groups)),
                          Tab(text: 'Subordinates', icon: Icon(Icons.account_tree)),
                          Tab(text: 'Raw Data', icon: Icon(Icons.table_chart)),
                        ],
                        isScrollable: true,
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildUsersView(),
                            _buildTeamsView(),
                            _buildSubordinatesView(),
                            _buildRawDataView(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildUsersView() {
    final s = _snapshot;
    if (s == null) return const Center(child: Text('No data'));

    final appUsers = (s['appUsers'] as List<dynamic>?) ?? [];
    final userRoleMapping = (s['userRoleMapping'] as List<dynamic>?) ?? [];
    final roles = (s['roles'] as List<dynamic>?) ?? [];
    final staff = (s['staff'] as List<dynamic>?) ?? [];
    final teams = (s['teams'] as List<dynamic>?) ?? [];
    final teamMembers = (s['teamMembers'] as List<dynamic>?) ?? [];
    final subordinateMapping = (s['subordinateMapping'] as List<dynamic>?) ?? [];

    // Create maps for lookups
    final roleMap = <String, String>{};
    for (final r in roles) {
      final role = r as Map<String, dynamic>;
      roleMap[role['id'] as String] = role['app_id'] as String? ?? '';
    }

    final staffMap = <String, Map<String, dynamic>>{};
    for (final s in staff) {
      final st = s as Map<String, dynamic>;
      staffMap[st['id'] as String] = st;
    }

    final teamMap = <String, Map<String, dynamic>>{};
    for (final t in teams) {
      final team = t as Map<String, dynamic>;
      teamMap[team['id'] as String] = team;
    }

    final userRoleMap = <String, String>{};
    for (final urm in userRoleMapping) {
      final m = urm as Map<String, dynamic>;
      final userId = m['app_user_id'] as String;
      final roleId = m['role_id'] as String;
      userRoleMap[userId] = roleMap[roleId] ?? 'unknown';
    }

    // Build staff-to-user map
    final staffToUserMap = <String, Map<String, dynamic>>{};
    for (final u in appUsers) {
      final user = u as Map<String, dynamic>;
      final staffId = user['staff_id'] as String?;
      if (staffId != null) {
        staffToUserMap[staffId] = user;
      }
    }

    // Build team members by staff
    final staffTeamsMap = <String, List<Map<String, dynamic>>>{};
    for (final tm in teamMembers) {
      final m = tm as Map<String, dynamic>;
      final staffId = m['staff_id'] as String;
      staffTeamsMap.putIfAbsent(staffId, () => []).add(m);
    }

    // Build subordinate relationships
    final supervisorMap = <String, String>{}; // subordinate_staff_id -> supervisor_staff_id
    final subordinatesMap = <String, List<String>>{}; // supervisor_staff_id -> [subordinate_staff_ids]
    for (final sub in subordinateMapping) {
      final m = sub as Map<String, dynamic>;
      final supId = m['supervisor_staff_id'] as String;
      final subId = m['subordinate_staff_id'] as String;
      supervisorMap[subId] = supId;
      subordinatesMap.putIfAbsent(supId, () => []).add(subId);
    }

    // Filter users based on search query
    final query = _userSearchQuery.trim().toLowerCase();
    final filteredUsers = appUsers.where((u) {
      if (query.isEmpty) return true;
      final user = u as Map<String, dynamic>;
      // Get email - handle null and convert to string
      final emailRaw = user['email'];
      final email = emailRaw != null ? emailRaw.toString().trim().toLowerCase() : '';
      
      // Get display name
      final displayNameRaw = user['display_name'];
      final displayName = displayNameRaw != null ? displayNameRaw.toString().trim().toLowerCase() : '';
      
      // Get staff info
      final staffId = user['staff_id'] as String?;
      final staffInfo = staffId != null ? staffMap[staffId] : null;
      final staffNameRaw = staffInfo?['name'];
      final staffName = staffNameRaw != null ? staffNameRaw.toString().trim().toLowerCase() : '';
      final staffAppIdRaw = staffInfo?['app_id'];
      final staffAppId = staffAppIdRaw != null ? staffAppIdRaw.toString().trim().toLowerCase() : '';
      
      // Search in all fields
      return email.isNotEmpty && email.contains(query) ||
          displayName.isNotEmpty && displayName.contains(query) ||
          staffName.isNotEmpty && staffName.contains(query) ||
          staffAppId.isNotEmpty && staffAppId.contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Users with Roles',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _userSearchController,
                  decoration: InputDecoration(
                    labelText: 'Search users (email, name, staff)',
                    hintText: 'e.g., leec2@hku.hk',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _userSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _userSearchController.clear();
                              setState(() => _userSearchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() => _userSearchQuery = value);
                  },
                ),
                const SizedBox(height: 8),
                if (filteredUsers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No users found'),
                  )
                else
                  ...filteredUsers.map((u) {
                    final user = u as Map<String, dynamic>;
                    final userId = user['id'] as String;
                    final role = userRoleMap[userId] ?? 'no role';
                    final staffId = user['staff_id'] as String?;
                    final staffInfo = staffId != null
                        ? staffMap[staffId]
                        : null;
                    final staffName = staffInfo?['name'] as String? ?? '';
                    final staffAppId = staffInfo?['app_id'] as String? ?? '';

                    // Get teams for this staff
                    final userTeams = staffId != null
                        ? staffTeamsMap[staffId] ?? []
                        : <Map<String, dynamic>>[];
                    final supervisorStaffId = staffId != null
                        ? supervisorMap[staffId]
                        : null;
                    final supervisorInfo = supervisorStaffId != null
                        ? staffMap[supervisorStaffId]
                        : null;
                    final subordinates = staffId != null
                        ? subordinatesMap[staffId] ?? []
                        : <String>[];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(user['email'] as String? ?? ''),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Display: ${user['display_name'] ?? ''}'),
                            if (staffName.isNotEmpty)
                              Text('Staff: $staffName ($staffAppId)'),
                            Text('Role: $role',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: role == 'sys_admin'
                                        ? Colors.red
                                        : role == 'dept_head'
                                            ? Colors.blue
                                            : Colors.grey)),
                            if (userTeams.isNotEmpty)
                              Text(
                                  'Teams: ${userTeams.length}',
                                  style: const TextStyle(fontSize: 12)),
                            if (supervisorInfo != null)
                              Text(
                                  'Supervisor: ${supervisorInfo['name']}',
                                  style: const TextStyle(fontSize: 12)),
                            if (subordinates.isNotEmpty)
                              Text(
                                  'Subordinates: ${subordinates.length}',
                                  style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        leading: CircleAvatar(
                          child: Text(
                              (user['email'] as String? ?? 'U')[0].toUpperCase()),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          _showUserDetails(
                            context,
                            user,
                            role,
                            staffInfo,
                            userTeams,
                            teamMap,
                            supervisorInfo,
                            subordinates,
                            staffMap,
                          );
                        },
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildUserForm(),
      ],
    );
  }

  void _showUserDetails(
    BuildContext context,
    Map<String, dynamic> user,
    String role,
    Map<String, dynamic>? staffInfo,
    List<Map<String, dynamic>> userTeams,
    Map<String, dynamic> teamMap,
    Map<String, dynamic>? supervisorInfo,
    List<String> subordinateStaffIds,
    Map<String, dynamic> staffMap,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user['email'] as String? ?? 'User Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Email', user['email'] as String? ?? ''),
              _buildDetailRow('Display Name', user['display_name'] as String? ?? ''),
              _buildDetailRow('Firebase UID', user['firebase_uid'] as String? ?? ''),
              const Divider(),
              if (staffInfo != null) ...[
                _buildDetailRow('Staff Name', staffInfo['name'] as String? ?? ''),
                _buildDetailRow('Staff App ID', staffInfo['app_id'] as String? ?? ''),
                const Divider(),
              ],
              _buildDetailRow('User Role', role,
                  color: role == 'sys_admin'
                      ? Colors.red
                      : role == 'dept_head'
                          ? Colors.blue
                          : Colors.grey),
              const Divider(),
              const Text('Teams:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (userTeams.isEmpty)
                const Text('  No team memberships', style: TextStyle(fontSize: 12))
              else
                ...userTeams.map((tm) {
                  final teamId = tm['team_id'] as String;
                  final team = teamMap[teamId];
                  final teamName = team?['name'] as String? ?? 'Unknown';
                  final teamAppId = team?['app_id'] as String? ?? '';
                  final teamRole = tm['role'] as String? ?? 'member';
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          teamRole == 'lead' ? Icons.star : Icons.group,
                          size: 16,
                          color: teamRole == 'lead' ? Colors.amber : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$teamName ($teamAppId) - $teamRole',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const Divider(),
              const Text('Supervisor:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (supervisorInfo == null)
                const Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Text('  No supervisor', style: TextStyle(fontSize: 12)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '  ${supervisorInfo['name']} (${supervisorInfo['app_id']})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              const Text('Subordinates:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (subordinateStaffIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Text('  No subordinates', style: TextStyle(fontSize: 12)),
                )
              else
                ...subordinateStaffIds.map((subId) {
                  final subInfo = staffMap[subId];
                  final subName = subInfo?['name'] as String? ?? 'Unknown';
                  final subAppId = subInfo?['app_id'] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_right, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$subName ($subAppId)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamsView() {
    final s = _snapshot;
    if (s == null) return const Center(child: Text('No data'));

    final teams = (s['teams'] as List<dynamic>?) ?? [];
    final teamMembers = (s['teamMembers'] as List<dynamic>?) ?? [];
    final staff = (s['staff'] as List<dynamic>?) ?? [];

    // Create maps
    final staffMap = <String, Map<String, dynamic>>{};
    for (final s in staff) {
      final st = s as Map<String, dynamic>;
      staffMap[st['id'] as String] = st;
    }

    final teamMembersMap = <String, List<Map<String, dynamic>>>{};
    for (final tm in teamMembers) {
      final m = tm as Map<String, dynamic>;
      final teamId = m['team_id'] as String;
      teamMembersMap.putIfAbsent(teamId, () => []).add(m);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Teams with Members',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (teams.isEmpty)
                  const Text('No teams found')
                else
                  ...teams.map((t) {
                    final team = t as Map<String, dynamic>;
                    final teamId = team['id'] as String;
                    final members = teamMembersMap[teamId] ?? [];
                    final teamName = team['name'] as String? ?? '';
                    final teamAppId = team['app_id'] as String? ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(teamName,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('app_id: $teamAppId'),
                        children: [
                          if (members.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No members'),
                            )
                          else
                            ...members.map((m) {
                              final staffId = m['staff_id'] as String;
                              final role = m['role'] as String? ?? 'member';
                              final staffInfo = staffMap[staffId];
                              final staffName =
                                  staffInfo?['name'] as String? ?? 'Unknown';
                              final staffAppId =
                                  staffInfo?['app_id'] as String? ?? '';

                              return ListTile(
                                leading: Icon(
                                  role == 'lead' ? Icons.star : Icons.person,
                                  color: role == 'lead'
                                      ? Colors.amber
                                      : Colors.grey,
                                ),
                                title: Text(staffName),
                                subtitle: Text(staffAppId),
                                trailing: Chip(
                                  label: Text(role),
                                  backgroundColor: role == 'lead'
                                      ? Colors.amber.shade100
                                      : Colors.grey.shade200,
                                ),
                              );
                            }),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildTeamForm(),
      ],
    );
  }

  Widget _buildSubordinatesView() {
    final s = _snapshot;
    if (s == null) return const Center(child: Text('No data'));

    final subordinateMapping =
        (s['subordinateMapping'] as List<dynamic>?) ?? [];
    final staff = (s['staff'] as List<dynamic>?) ?? [];

    // Create staff map
    final staffMap = <String, Map<String, dynamic>>{};
    for (final st in staff) {
      final s = st as Map<String, dynamic>;
      staffMap[s['id'] as String] = s;
    }

    // Group by supervisor
    final supervisorMap = <String, List<Map<String, dynamic>>>{};
    for (final sub in subordinateMapping) {
      final m = sub as Map<String, dynamic>;
      final supId = m['supervisor_staff_id'] as String;
      supervisorMap.putIfAbsent(supId, () => []).add(m);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Subordinate Relationships',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (supervisorMap.isEmpty)
                  const Text('No subordinate relationships found')
                else
                  ...supervisorMap.entries.map((entry) {
                    final supId = entry.key;
                    final subordinates = entry.value;
                    final supInfo = staffMap[supId];
                    final supName = supInfo?['name'] as String? ?? 'Unknown';
                    final supAppId = supInfo?['app_id'] as String? ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: const Icon(Icons.person_outline,
                            color: Colors.blue),
                        title: Text(supName,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Supervisor: $supAppId'),
                        children: [
                          ...subordinates.map((sub) {
                            final subId = sub['subordinate_staff_id'] as String;
                            final subInfo = staffMap[subId];
                            final subName =
                                subInfo?['name'] as String? ?? 'Unknown';
                            final subAppId =
                                subInfo?['app_id'] as String? ?? '';

                            return ListTile(
                              leading: const Icon(Icons.arrow_right,
                                  color: Colors.green),
                              title: Text(subName),
                              subtitle: Text('Subordinate: $subAppId'),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSubordinateForm(),
      ],
    );
  }

  Widget _buildRawDataView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSnapshotTables(),
          const SizedBox(height: 24),
          _buildUserForm(),
          const SizedBox(height: 24),
          _buildTeamForm(),
          const SizedBox(height: 24),
          _buildTeamMemberForm(),
          const SizedBox(height: 24),
          _buildSubordinateForm(),
        ],
      ),
    );
  }

  Widget _buildUserForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add / update user + role',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextField(
                        controller: _firebaseUid,
                        decoration: const InputDecoration(
                            labelText: 'Firebase UID',
                            hintText: 'from Firebase Auth'),
                      ),
                      TextField(
                        controller: _userEmail,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      TextField(
                        controller: _displayName,
                        decoration:
                            const InputDecoration(labelText: 'Display name'),
                      ),
                      TextField(
                        controller: _staffAppId,
                        decoration: const InputDecoration(
                            labelText: 'Staff app_id (optional)'),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _roleAppId,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                              value: 'sys_admin', child: Text('sys_admin')),
                          DropdownMenuItem(
                              value: 'dept_head', child: Text('dept_head')),
                          DropdownMenuItem(
                              value: 'staff', child: Text('staff')),
                        ],
                        onChanged: (v) =>
                            setState(() => _roleAppId = v ?? 'staff'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          final token = await user?.getIdToken();
                          if (token == null) return;
                          final ok = await BackendApi().adminUpsertUser(
                            idToken: token,
                            firebaseUid: _firebaseUid.text.trim(),
                            email: _userEmail.text.trim(),
                            displayName: _displayName.text.trim().isEmpty
                                ? null
                                : _displayName.text.trim(),
                            staffAppId: _staffAppId.text.trim().isEmpty
                                ? null
                                : _staffAppId.text.trim(),
                            roleAppId: _roleAppId,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(ok ? 'Saved' : 'Failed')),
                          );
                          if (ok) await _reload();
                        },
                        child: const Text('Save user'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _deleteAppUserId,
                        decoration: const InputDecoration(
                          labelText: 'Delete app user (UUID from App users table)',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final id = _deleteAppUserId.text.trim();
                          if (id.isEmpty) return;
                          final user = FirebaseAuth.instance.currentUser;
                          final token = await user?.getIdToken();
                          if (token == null) return;
                          final ok =
                              await BackendApi().adminDeleteUser(token, id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(ok ? 'Deleted' : 'Failed')),
                          );
                          if (ok) await _reload();
                        },
                        child: const Text('Delete user'),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add team',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextField(
                        controller: _teamName,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      TextField(
                        controller: _teamAppId,
                        decoration: const InputDecoration(
                            labelText: 'app_id (slug)'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          final token = await user?.getIdToken();
                          if (token == null) return;
                          final ok = await BackendApi().adminUpsertTeam(
                            idToken: token,
                            name: _teamName.text.trim(),
                            appId: _teamAppId.text.trim(),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(ok ? 'Saved' : 'Failed')),
                          );
                          if (ok) await _reload();
                        },
                        child: const Text('Save team'),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamMemberForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Team member',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextField(
                        controller: _tmTeam,
                        decoration: const InputDecoration(
                            labelText: 'Team app_id'),
                      ),
                      TextField(
                        controller: _tmStaff,
                        decoration: const InputDecoration(
                            labelText: 'Staff app_id'),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _tmRole,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                              value: 'lead', child: Text('lead')),
                          DropdownMenuItem(
                              value: 'member', child: Text('member')),
                        ],
                        onChanged: (v) =>
                            setState(() => _tmRole = v ?? 'member'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          final token = await user?.getIdToken();
                          if (token == null) return;
                          final ok = await BackendApi().adminTeamMember(
                            idToken: token,
                            teamAppId: _tmTeam.text.trim(),
                            staffAppId: _tmStaff.text.trim(),
                            role: _tmRole,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(ok ? 'Saved' : 'Failed')),
                          );
                          if (ok) await _reload();
                        },
                        child: const Text('Save team member'),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubordinateForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Subordinate mapping',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      TextField(
                        controller: _supStaff,
                        decoration: const InputDecoration(
                            labelText: 'Supervisor staff app_id'),
                      ),
                      TextField(
                        controller: _subStaff,
                        decoration: const InputDecoration(
                            labelText: 'Subordinate staff app_id'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          final token = await user?.getIdToken();
                          if (token == null) return;
                          final ok = await BackendApi().adminSubordinate(
                            idToken: token,
                            supervisorStaffAppId: _supStaff.text.trim(),
                            subordinateStaffAppId: _subStaff.text.trim(),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(ok ? 'Saved' : 'Failed')),
                          );
                          if (ok) await _reload();
                        },
                        child: const Text('Save subordinate'),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotTables() {
    final s = _snapshot;
    if (s == null) return const SizedBox.shrink();

    Widget table(String title, List<dynamic>? rows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (rows == null || rows.isEmpty)
            const Text('(empty)')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: _columnsForRow(rows.first as Map<String, dynamic>),
                rows: rows
                    .map((e) => DataRow(
                        cells: _cellsForRow(e as Map<String, dynamic>)))
                    .toList(),
              ),
            ),
          const SizedBox(height: 16),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        table('Teams', s['teams'] as List<dynamic>?),
        table('Roles', s['roles'] as List<dynamic>?),
        table('Staff', s['staff'] as List<dynamic>?),
        table('App users', s['appUsers'] as List<dynamic>?),
        table('User role mapping', s['userRoleMapping'] as List<dynamic>?),
        table('Team members', s['teamMembers'] as List<dynamic>?),
        table('Subordinate mapping', s['subordinateMapping'] as List<dynamic>?),
      ],
    );
  }

  List<DataColumn> _columnsForRow(Map<String, dynamic> row) {
    return row.keys
        .map((k) => DataColumn(label: Text(k.toString())))
        .toList();
  }

  List<DataCell> _cellsForRow(Map<String, dynamic> row) {
    return row.values
        .map((v) => DataCell(Text(v == null ? '' : v.toString())))
        .toList();
  }
}
