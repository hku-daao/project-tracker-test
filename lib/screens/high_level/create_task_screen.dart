import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/assignee.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../models/team.dart';
import '../../priority.dart';
import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';
import '../../widgets/staff_assignee_picker_panel.dart';

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentsController = TextEditingController();
  final Set<String> _selectedTeamIds = {};
  final Set<String> _selectedAssigneeIds = {};
  int _priority = 1; // 1 = Standard, 2 = Urgent
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loadingProfile = false;
  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  bool _pickerLoading = false;
  String? _pickerError;
  final Map<String, String> _staffAssigneeToTeamId = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndReloadProfile();
      _loadSupabaseAssigneePicker();
    });
  }

  static int _dateOnlyCompare(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return da.compareTo(db);
  }

  Future<void> _loadSupabaseAssigneePicker() async {
    if (!SupabaseConfig.isConfigured) return;
    setState(() {
      _pickerLoading = true;
      _pickerError = null;
    });
    try {
      final data = await SupabaseService.fetchStaffAssigneePickerData();
      if (!mounted) return;
      setState(() {
        _pickerLoading = false;
        if (data != null) {
          _pickerTeams = data.teams;
          _pickerStaff = data.staff;
          _staffAssigneeToTeamId.clear();
          for (final s in data.staff) {
            if (s.teamId != null && s.teamId!.isNotEmpty) {
              _staffAssigneeToTeamId[s.assigneeId] = s.teamId!;
            }
          }
        } else {
          _pickerTeams = [];
          _pickerStaff = [];
          _staffAssigneeToTeamId.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pickerLoading = false;
        _pickerError = e.toString();
        _pickerTeams = [];
        _pickerStaff = [];
        _staffAssigneeToTeamId.clear();
      });
    }
  }

  /// Local [teamId] hint from Supabase picker: first selected assignee’s `staff.team_id` (by name order).
  String _inferTeamIdFromSupabasePick(List<String> directorIds) {
    if (directorIds.isEmpty) return '';
    final sorted = [...directorIds]..sort((a, b) {
        final na = _pickerStaff
            .firstWhere((s) => s.assigneeId == a,
                orElse: () =>
                    StaffForAssignment(assigneeId: a, name: a))
            .name;
        final nb = _pickerStaff
            .firstWhere((s) => s.assigneeId == b,
                orElse: () =>
                    StaffForAssignment(assigneeId: b, name: b))
            .name;
        return na.compareTo(nb);
      });
    for (final id in sorted) {
      final t = _staffAssigneeToTeamId[id];
      if (t != null && t.isNotEmpty) return t;
    }
    return '';
  }

  Future<void> _checkAndReloadProfile() async {
    final state = context.read<AppState>();
    if (state.userRole == null && !_loadingProfile) {
      _loadingProfile = true;
      try {
        final user = FirebaseAuth.instance.currentUser;
        final token = await user?.getIdToken(true);
        if (token != null) {
          final profile = await BackendApi().getMe(token);
          if (mounted && profile != null && profile.role != null) {
            state.setUserProfile(
              role: profile.role,
              staffAppId: profile.staffAppId,
              assignableStaff: profile.assignableStaff,
            );
            if (mounted) {
              await state.loadTeamsAndStaff(token);
            }
          }
        }
      } catch (e) {
        debugPrint('CreateTaskScreen: Error reloading profile: $e');
      } finally {
        if (mounted) {
          setState(() => _loadingProfile = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  List<Assignee> _assigneesForSelectedTeams() {
    if (_selectedTeamIds.isEmpty) return [];
    return context.read<AppState>().getAssigneesForTeams(_selectedTeamIds.toList());
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final useServer = state.assignableStaffFromServer.isNotEmpty;
    final role = state.userRole?.toLowerCase().trim();

    String teamId;
    List<String> directorIds;
    final teams = state.teams;
    
    // General role: can only assign to themselves
    if (role == 'general') {
      if (useServer && state.assignableStaffFromServer.isNotEmpty) {
        final single = state.assignableStaffFromServer.first;
        directorIds = [single.staffAppId];
        teamId = single.teamAppId ?? (teams.isNotEmpty ? teams.first.id : '');
      } else {
        // Fallback: use user's own staff_app_id
        final userStaffAppId = state.userStaffAppId;
        if (userStaffAppId == null || userStaffAppId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No staff profile found. Please contact your administrator.')),
          );
          return;
        }
        directorIds = [userStaffAppId];
        teamId = teams.isNotEmpty ? teams.first.id : '';
      }
    } 
    // Supervisor: can only select subordinates (already filtered by backend)
    else if (role == 'supervisor') {
      if (useServer && _selectedAssigneeIds.isNotEmpty) {
        directorIds = _selectedAssigneeIds.toList();
        // Get team from first selected assignee
        final firstAssignee = state.assignableStaffFromServer
            .firstWhere((e) => e.staffAppId == directorIds.first,
                orElse: () => state.assignableStaffFromServer.first);
        teamId = firstAssignee.teamAppId ?? (teams.isNotEmpty ? teams.first.id : '');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one subordinate')),
        );
        return;
      }
    }
    // sys_admin and dept_head: can select all teams and team members
    else if (role == 'sys_admin' || role == 'dept_head') {
      if (_pickerStaff.isNotEmpty) {
        directorIds = _selectedAssigneeIds.toList();
        if (directorIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one assignee')),
          );
          return;
        }
        teamId = _inferTeamIdFromSupabasePick(directorIds);
        if (teamId.isEmpty) {
          teamId = teams.isNotEmpty ? teams.first.id : '';
        }
      } else if (useServer) {
        // Using server assignable staff
        directorIds = _selectedAssigneeIds.toList();
        if (directorIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one assignee')),
          );
          return;
        }
        // Get team from selected assignee or selected team
        if (_selectedTeamIds.isNotEmpty) {
          teamId = _selectedTeamIds.first;
        } else {
          // Try to get team from first selected assignee
          final firstAssignee = state.assignableStaffFromServer
              .firstWhere((e) => e.staffAppId == directorIds.first,
                  orElse: () => state.assignableStaffFromServer.first);
          teamId = firstAssignee.teamAppId ?? (teams.isNotEmpty ? teams.first.id : '');
        }
      } else {
        // Not using server - use database teams and assignees
        if (_selectedTeamIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one team')),
          );
          return;
        }
        if (_selectedAssigneeIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one Director or Responsible Officer')),
          );
          return;
        }
        teamId = _selectedTeamIds.first;
        directorIds = _selectedAssigneeIds.toList();
      }
    } else {
      // Debug: show what role we got
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unknown role: "$role". Please contact your administrator.')),
      );
      return;
    }
    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    final priority = _priority;
    final capturedStart = _startDate;
    final capturedEnd = _endDate;
    final commentText = _commentsController.text.trim();

    if (capturedStart != null &&
        capturedEnd != null &&
        _dateOnlyCompare(capturedStart, capturedEnd) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start date cannot be after due date.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final localId = state.addTask(
      name: name,
      description: description,
      assigneeIds: directorIds,
      priority: priority,
      teamId: teamId.isEmpty ? null : teamId,
      status: TaskStatus.todo,
      startDate: capturedStart,
      endDate: capturedEnd,
    );

    String? cloudErr;
    String? insertedTaskId;
    if (SupabaseConfig.isConfigured) {
      final slots = await SupabaseService.assigneeSlotsForTask(directorIds);
      final ins = await SupabaseService.insertTaskTableRow(
        taskName: name,
        assignees: slots,
        priority: priorityToDisplayName(priority),
        startDate: capturedStart,
        dueDate: capturedEnd,
        description: description.isEmpty ? null : description,
        status: 'Incomplete',
        creatorStaffLookupKey: state.userStaffAppId,
      );
      cloudErr = ins.error;
      insertedTaskId = ins.taskId;
    }

    if (commentText.isNotEmpty) {
      if (SupabaseConfig.isConfigured && cloudErr == null && insertedTaskId != null) {
        final cErr = await SupabaseService.insertSingularCommentRow(
          taskId: insertedTaskId,
          description: commentText,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (!mounted) return;
        if (cErr != null) {
          showCopyableSnackBar(
            context,
            'Task created, but comment was not saved: $cErr',
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 10),
          );
        }
      } else if (!SupabaseConfig.isConfigured) {
        final userId = state.userStaffAppId;
        final String authorId;
        final String authorName;
        if (userId != null && userId.isNotEmpty) {
          authorId = userId;
          authorName = state.assigneeById(userId)?.name ?? userId;
        } else {
          authorId = directorIds.isNotEmpty
              ? directorIds.first
              : state.assignees.first.id;
          final author = state.assigneeById(authorId);
          authorName = author?.name ?? authorId;
        }
        state.addComment(
          taskId: localId,
          authorId: authorId,
          authorName: authorName,
          body: commentText,
        );
      }
    }

    _nameController.clear();
    _descController.clear();
    _commentsController.clear();
    setState(() {
      _selectedTeamIds.clear();
      _selectedAssigneeIds.clear();
      _priority = 1;
      _startDate = null;
      _endDate = null;
    });

    if (!mounted) return;

    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(
        context,
        'Saved in this browser only. Set Supabase anon key for this environment (see docs/ENVIRONMENTS.md), rebuild web, redeploy — then data survives refresh.',
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 10),
      );
    } else if (cloudErr != null) {
      showCopyableSnackBar(
        context,
        'Could not save to Supabase: $cloudErr',
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 14),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task saved to Supabase.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  /// Assignees from server (RBAC); when non-empty, team/assignee UI uses this.
  List<AssignableStaffEntry> get _serverAssignable =>
      context.read<AppState>().assignableStaffFromServer;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final useServer = _serverAssignable.isNotEmpty;
    final role = state.userRole?.toLowerCase().trim();
    final assignees = _assigneesForSelectedTeams();

    // Filter assignees based on role and selected teams
    List<AssignableStaffEntry> serverAssigneesFiltered = [];
    if (useServer) {
      if (role == 'sys_admin' || role == 'dept_head') {
        // For sys_admin/dept_head: show all assignable staff, optionally filtered by selected teams
        if (_selectedTeamIds.isEmpty) {
          // No team filter: show all assignable staff
          serverAssigneesFiltered = _serverAssignable;
        } else {
          // Filter by selected teams
          serverAssigneesFiltered = _serverAssignable
              .where((e) => e.teamAppId != null && _selectedTeamIds.contains(e.teamAppId))
              .toList();
        }
      } else {
        // For supervisor and general: show all assignable staff (already filtered by backend)
        serverAssigneesFiltered = _serverAssignable;
      }
    }
    
    // Debug: Log role and useServer status
    if (role == null) {
      debugPrint('WARNING: userRole is null in CreateTaskScreen');
    } else {
      debugPrint('CreateTaskScreen: role=$role, useServer=$useServer, teams=${state.teams.length}, assignableStaff=${_serverAssignable.length}');
    }

    final useSupabasePicker = SupabaseConfig.isConfigured &&
        (role == 'sys_admin' || role == 'dept_head') &&
        _pickerStaff.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (role == 'sys_admin' || role == 'dept_head') ...[
              if (SupabaseConfig.isConfigured && _pickerLoading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
              ],
              if (SupabaseConfig.isConfigured && _pickerError != null && !_pickerLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _pickerError!,
                    style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                  ),
                ),
              if (useSupabasePicker)
                StaffAssigneePickerPanel(
                  teams: _pickerTeams,
                  staff: _pickerStaff,
                  selectedIds: _selectedAssigneeIds,
                  onSelectionChanged: (s) => setState(() {
                    _selectedAssigneeIds
                      ..clear()
                      ..addAll(s);
                  }),
                )
              else ...[
              const Text(
                'Team (multiple)',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final state = context.read<AppState>();
                  final teams = state.teams;
                  if (teams.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No teams found in database.',
                            style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Please ensure:\n'
                            '1. Teams exist in the "teams" table\n'
                            '2. Backend /api/teams endpoint is working\n'
                            '3. Check backend server logs for errors',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: teams.map((Team t) {
                      final selected = _selectedTeamIds.contains(t.id);
                      return FilterChip(
                        label: Text(t.name),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedTeamIds.add(t.id);
                            } else {
                              _selectedTeamIds.remove(t.id);
                              // Remove assignees that were only in this team
                              if (useServer) {
                                _selectedAssigneeIds.removeWhere((id) {
                                  final assignee = _serverAssignable.firstWhere(
                                    (e) => e.staffAppId == id,
                                    orElse: () => const AssignableStaffEntry(
                                      staffAppId: '',
                                      staffName: '',
                                      teamAppId: null,
                                      teamName: null,
                                    ),
                                  );
                                  // Remove if this was the only selected team for this assignee
                                  return assignee.teamAppId == t.id &&
                                      !_selectedTeamIds.any((tid) {
                                        final otherAssignee = _serverAssignable.firstWhere(
                                          (e) => e.staffAppId == id,
                                          orElse: () => const AssignableStaffEntry(
                                            staffAppId: '',
                                            staffName: '',
                                            teamAppId: null,
                                            teamName: null,
                                          ),
                                        );
                                        return otherAssignee.teamAppId == tid;
                                      });
                                });
                              } else {
                                // Remove assignees from this team when not using server
                                for (final id in [...t.directorIds, ...t.officerIds]) {
                                  final inOther = teams.any((x) =>
                                      x.id != t.id &&
                                      _selectedTeamIds.contains(x.id) &&
                                      (x.directorIds.contains(id) || x.officerIds.contains(id)));
                                  if (!inOther) _selectedAssigneeIds.remove(id);
                                }
                              }
                            }
                          });
                        },
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
              ],
            ],
            if (!useSupabasePicker) ...[
            Text(
              useServer ? 'Assignees (multiple)' : 'Directors & Responsible Officers (multiple)',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            if (useServer) ...[
              // General role: can only assign to themselves
              if (role == 'general')
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Chip(
                    label: Text(serverAssigneesFiltered.isNotEmpty 
                        ? serverAssigneesFiltered.first.staffName 
                        : 'Yourself'),
                    backgroundColor: Colors.blue.shade100,
                  ),
                )
              // Supervisor: can only select subordinates (already filtered by backend)
              // sys_admin/dept_head: can select all team members
              else if (serverAssigneesFiltered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role == 'supervisor'
                            ? 'No subordinates found.'
                            : role == 'dept_head' || role == 'sys_admin'
                                ? 'No assignable staff found from backend.'
                                : 'No assignable staff found.',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                      ),
                      if (role == 'dept_head' || role == 'sys_admin') ...[
                        const SizedBox(height: 4),
                        Text(
                          'For dept_head/sys_admin, you can still select team members from database teams below if teams are available.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: serverAssigneesFiltered.map((e) {
                    final selected = _selectedAssigneeIds.contains(e.staffAppId);
                    return FilterChip(
                      label: Text(e.staffName),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedAssigneeIds.add(e.staffAppId);
                            // Auto-select team for sys_admin/dept_head
                            if ((role == 'sys_admin' || role == 'dept_head') && e.teamAppId != null) {
                              _selectedTeamIds.add(e.teamAppId!);
                            }
                          } else {
                            _selectedAssigneeIds.remove(e.staffAppId);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
            ] else ...[
              // Fallback when not using server: show team members
              if ((role == 'sys_admin' || role == 'dept_head') && _selectedTeamIds.isEmpty)
                const Text(
                  'Select team(s) first',
                  style: TextStyle(color: Colors.grey),
                )
              else if ((role == 'sys_admin' || role == 'dept_head'))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: assignees.map((a) {
                    final selected = _selectedAssigneeIds.contains(a.id);
                    final isDirector = state.isDirector(a.id);
                    return FilterChip(
                      label: Text(a.name),
                      selected: selected,
                      backgroundColor: isDirector ? Colors.lightBlue.shade100 : Colors.purple.shade100,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedAssigneeIds.add(a.id);
                          } else {
                            _selectedAssigneeIds.remove(a.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                )
              else
                const Text(
                  'Please ensure backend is configured for role-based assignment.',
                  style: TextStyle(color: Colors.grey),
                ),
            ],
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Task name',
                hintText: 'Task name',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const Text('Priority', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: priorityOptions.map((p) {
                final selected = _priority == p;
                return FilterChip(
                  label: Text(priorityToDisplayName(p)),
                  selected: selected,
                  onSelected: (v) => setState(() => _priority = p),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Start Date', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _startDate != null
                      ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                      : 'Not set',
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: _endDate ?? DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (d != null) setState(() => _startDate = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Pick'),
                ),
                if (_startDate != null)
                  TextButton(
                    onPressed: () => setState(() => _startDate = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Due Date', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _endDate != null
                      ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                      : 'Not set',
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? _endDate ?? DateTime.now(),
                      firstDate: _startDate ?? DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (d != null) setState(() => _endDate = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Pick'),
                ),
                if (_endDate != null)
                  TextButton(
                    onPressed: () => setState(() => _endDate = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _commentsController,
              decoration: const InputDecoration(
                labelText: 'Comments',
                hintText: 'Comments',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Create task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
