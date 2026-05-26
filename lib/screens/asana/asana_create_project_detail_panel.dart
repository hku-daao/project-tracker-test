import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';
import '../../utils/hk_time.dart';
import '../../utils/holiday_date_picker.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_widgets.dart';

/// New project slide — empty fields, Create in footer.
class AsanaCreateProjectDetailPanel extends StatefulWidget {
  const AsanaCreateProjectDetailPanel({
    super.key,
    required this.palette,
    required this.onClose,
  });

  final AsanaLandingPalette palette;
  final VoidCallback onClose;

  @override
  State<AsanaCreateProjectDetailPanel> createState() =>
      _AsanaCreateProjectDetailPanelState();
}

class _AsanaCreateProjectDetailPanelState
    extends State<AsanaCreateProjectDetailPanel> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = HkTime.todayDateOnlyHk();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
  }

  Future<void> _pickDate({required bool isStart}) async {
    final today = HkTime.todayDateOnlyHk();
    final picked = await showHolidayAwareDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? today,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _create(AppState state) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showCopyableSnackBar(
        context,
        'Project name is required',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (_startDate != null &&
        _endDate != null &&
        _startDate!.isAfter(_endDate!)) {
      showCopyableSnackBar(
        context,
        'Start date cannot be after due date',
        backgroundColor: Colors.orange,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final ins = await SupabaseService.insertProjectRow(
        name: name,
        description: _descController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (ins.error != null && mounted) {
        showCopyableSnackBar(context, ins.error!, backgroundColor: Colors.orange);
        return;
      }
      final newId = ins.projectId;
      if (newId != null && newId.isNotEmpty) {
        final p = await SupabaseService.fetchProjectById(newId);
        if (p != null) state.upsertProject(p);
      }
      if (mounted) widget.onClose();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chrome = AsanaSlideChrome(widget.palette);
    final creatorName = () {
      final id = state.userStaffAppId?.trim();
      if (id == null || id.isEmpty) return '';
      return state.assigneeById(id)?.name.trim() ?? id;
    }();

    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: AsanaDetailSlideFooter(
        backgroundColor: chrome.footer,
        borderColor: chrome.footerBorder,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: _saving ? null : () => _create(state),
              style: FilledButton.styleFrom(
                backgroundColor: widget.palette.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(_saving ? 'Creating…' : 'Create'),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                AsanaHoverTextField(
                  controller: _nameController,
                  canEdit: true,
                  readOnly: _saving,
                  maxLines: 3,
                  minLines: 1,
                  style: asanaDetailTitleStyle(context),
                ),
                const SizedBox(height: 12),
                AsanaDetailLabelValue(
                  label: 'Description',
                  child: AsanaHoverTextField(
                    controller: _descController,
                    canEdit: true,
                    readOnly: _saving,
                    maxLines: 8,
                    minLines: 2,
                    style: asanaDetailMultilineValueStyle(context),
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Creator',
                  child: AsanaDetailPlainValue(text: creatorName),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'PIC',
                  child: const AsanaDetailPlainValue(text: ''),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Status',
                  child: const AsanaDetailStatusPill(status: 'Not started'),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Start date',
                  child: AsanaHoverTapValue(
                    value: _formatDate(_startDate),
                    canEdit: true,
                    onTap: (_) => _pickDate(isStart: true),
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Due date',
                  child: AsanaHoverTapValue(
                    value: _formatDate(_endDate),
                    canEdit: true,
                    onTap: (_) => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
    );
  }
}
