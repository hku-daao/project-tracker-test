import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/project_record.dart';
import '../../services/supabase_service.dart';
import '../../utils/hk_time.dart';
import 'asana_detail_widgets.dart';

class AsanaProjectDetailPanel extends StatefulWidget {
  const AsanaProjectDetailPanel({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  State<AsanaProjectDetailPanel> createState() => _AsanaProjectDetailPanelState();
}

class _AsanaProjectDetailPanelState extends State<AsanaProjectDetailPanel> {
  ProjectRecord? _project;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AsanaProjectDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (SupabaseConfig.isConfigured) {
      final p = await SupabaseService.fetchProjectById(widget.projectId);
      if (mounted) setState(() => _project = p);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.expand(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final p = _project;
    if (p == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Project not found')),
      );
    }
    final state = context.watch<AppState>();

    String picLine() {
      if (p.picStaffDisplayNames.isNotEmpty) {
        return p.picStaffDisplayNames.join(', ');
      }
      if (p.picStaffUuids.isEmpty) return '';
      return p.picStaffUuids
          .map((u) => state.assigneeById(u)?.name ?? u)
          .join(', ');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p.name.trim().isEmpty ? '(Unnamed project)' : p.name.trim(),
            style: asanaDetailTitleStyle(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          AsanaDetailLabelValue(
            label: 'Description',
            child: Text(
              p.description.trim(),
              style: asanaDetailMultilineValueStyle(context),
            ),
          ),
          if ((p.createByDisplayName ?? '').trim().isNotEmpty)
            AsanaDetailTwoColumnRow(
              label: 'Creator',
              child: AsanaDetailPlainValue(text: p.createByDisplayName!.trim()),
            ),
          AsanaDetailTwoColumnRow(
            label: 'PIC',
            child: AsanaDetailPlainValue(text: picLine()),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Status',
            child: AsanaDetailStatusPill(status: p.status),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Start date',
            child: AsanaDetailPlainValue(text: _date(p.startDate)),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Due date',
            child: AsanaDetailPlainValue(text: _date(p.endDate)),
          ),
          if ((p.updateByDisplayName ?? '').trim().isNotEmpty)
            AsanaDetailTwoColumnRow(
              label: 'Last updated by',
              child: AsanaDetailPlainValue(text: p.updateByDisplayName!.trim()),
            ),
          if (p.updateDate != null)
            AsanaDetailTwoColumnRow(
              label: 'Last updated',
              child: AsanaDetailPlainValue(text: _date(p.updateDate)),
            ),
        ],
      ),
    );
  }
}
