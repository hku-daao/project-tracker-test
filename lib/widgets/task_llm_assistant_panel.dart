import 'package:flutter/material.dart';

import '../services/deepseek_service.dart';

/// In-form LLM helper: user prompt → suggested name/description → apply to fields.
class TaskLlmAssistantPanel extends StatefulWidget {
  const TaskLlmAssistantPanel({
    super.key,
    required this.nameController,
    required this.descController,
    required this.readOnly,
    this.extraContext,
    this.promptLabelText = 'What should this task be about?',
  });

  final TextEditingController nameController;
  final TextEditingController descController;
  final bool readOnly;
  final String? extraContext;

  /// Label for the prompt [TextField] (e.g. task vs sub-task wording).
  final String promptLabelText;

  @override
  State<TaskLlmAssistantPanel> createState() => _TaskLlmAssistantPanelState();
}

class _TaskLlmAssistantPanelState extends State<TaskLlmAssistantPanel> {
  final _promptController = TextEditingController();
  final ScrollController _previewScrollController = ScrollController();
  String? _error;
  bool _busy = false;
  String? _suggestedTitle;
  String? _suggestedDesc;
  String? _preview;

  static const double _kTouchMin = 48;
  static const double _kPreviewMaxHeight = 280;
  static const double _kApplyStackBreakpoint = 520;

  @override
  void dispose() {
    _promptController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (widget.readOnly || !DeepseekService.isConfigured) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _suggestedTitle = null;
      _suggestedDesc = null;
    });
    try {
      final r = await DeepseekService.suggestTitleDescription(
        userPrompt: _promptController.text,
        extraContext: widget.extraContext,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _suggestedTitle = r.title;
        _suggestedDesc = r.description;
        _preview =
            'Name: ${r.title}\n\nDescription: ${r.description}';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_previewScrollController.hasClients) {
          _previewScrollController.jumpTo(0);
        }
      });
    } catch (e, st) {
      debugPrint('$e\n$st');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  ButtonStyle _applyButtonStyle() {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, _kTouchMin),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  Widget _buildApplyButtons(BuildContext context, double maxWidth) {
    final stackVertically = maxWidth < _kApplyStackBreakpoint;
    final style = _applyButtonStyle();

    void applyName() => widget.nameController.text = _suggestedTitle!;
    void applyDesc() => widget.descController.text = _suggestedDesc!;
    void applyBoth() {
      if (_suggestedTitle != null) {
        widget.nameController.text = _suggestedTitle!;
      }
      if (_suggestedDesc != null) {
        widget.descController.text = _suggestedDesc!;
      }
    }

    Widget labeledButton({
      required VoidCallback? onPressed,
      required String label,
    }) {
      return OutlinedButton(
        style: style,
        onPressed: onPressed,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final nameBtn = labeledButton(
      onPressed: widget.readOnly || _suggestedTitle == null ? null : applyName,
      label: 'Apply name',
    );
    final descBtn = labeledButton(
      onPressed: widget.readOnly || _suggestedDesc == null ? null : applyDesc,
      label: 'Apply description',
    );
    final bothBtn = labeledButton(
      onPressed: widget.readOnly ||
              (_suggestedTitle == null && _suggestedDesc == null)
          ? null
          : applyBoth,
      label: 'Apply both',
    );

    if (stackVertically) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          nameBtn,
          const SizedBox(height: 10),
          descBtn,
          const SizedBox(height: 10),
          bothBtn,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: nameBtn),
        const SizedBox(width: 10),
        Expanded(child: descBtn),
        const SizedBox(width: 10),
        Expanded(child: bothBtn),
      ],
    );
  }

  /// Release `flutter build web` tree-shakes the Material Icons font; uncommon
  /// glyphs can be omitted so [Icon] paints nothing. These characters use the
  /// app text font (e.g. Noto Sans TC) and stay visible on testing/production.
  Widget _aiAssistantTitleGlyph(ThemeData theme) {
    return Text(
      String.fromCharCode(0x2726), // ✦ FOUR POINTED BLACK STAR
      style: TextStyle(
        fontSize: 20,
        height: 1.1,
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _suggestActionGlyph(ThemeData theme) {
    return Text(
      String.fromCharCode(0x27A4), // ➤ BLACK-FEATHERED RIGHTWARDS ARROW
      style: TextStyle(
        fontSize: 18,
        height: 1,
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildPreviewBox(ThemeData theme) {
    return Semantics(
      label: 'Suggested name and description preview',
      container: true,
      child: FocusTraversalGroup(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.45),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _kPreviewMaxHeight),
              child: Scrollbar(
                controller: _previewScrollController,
                thumbVisibility: true,
                radius: const Radius.circular(8),
                child: SingleChildScrollView(
                  controller: _previewScrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  child: SelectionArea(
                    child: Text(
                      _preview!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = DeepseekService.isConfigured;
    final suggestButtonStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, _kTouchMin),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 26,
                      height: 24,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _aiAssistantTitleGlyph(theme),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'AI assistant',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!configured) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Not configured. Build the web app with '
                    '--dart-define=DEEPSEEK_API_KEY=your_key',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _promptController,
                  readOnly: widget.readOnly || !configured,
                  minLines: 2,
                  maxLines: 8,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: widget.promptLabelText,
                    hintText: 'Paste notes, an email snippet, or bullet goals…',
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                    isDense: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    style: suggestButtonStyle,
                    onPressed: widget.readOnly || !configured || _busy
                        ? null
                        : _send,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_busy)
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        else
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Center(child: _suggestActionGlyph(theme)),
                          ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _busy
                                ? 'Please wait...'
                                : 'Suggest name & description',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      height: 1.4,
                    ),
                  ),
                ],
                if (_preview != null && _preview!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Preview',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildPreviewBox(theme),
                  const SizedBox(height: 12),
                  _buildApplyButtons(context, constraints.maxWidth),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
