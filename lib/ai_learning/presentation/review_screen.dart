import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../data/learning_models.dart';
import '../data/learning_repository.dart';

class ReviewArgs {
  const ReviewArgs({required this.submissionId, required this.panels});

  final String submissionId;
  final List<LearningPanel> panels;
}

/// Each detected panel and each suggested part gets a true or false verdict.
/// Save is blocked until every item has one, so the training data has no gaps.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.args});

  final ReviewArgs args;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final Map<String, bool> _panelVerdicts = {};
  final Map<String, bool> _partVerdicts = {};
  bool _busy = false;
  String? _message;

  int get _totalItems {
    var n = widget.args.panels.length;
    for (final p in widget.args.panels) {
      n += p.parts.length;
    }
    return n;
  }

  int get _answeredItems => _panelVerdicts.length + _partVerdicts.length;

  Future<void> _save() async {
    // Recap before writing: a verdict is unrecoverable once submitted, so show
    // what is about to be saved and let the respondent spot a mis-tap.
    final confirmed = _panelVerdicts.values.where((v) => v).length;
    final rejected = _panelVerdicts.values.where((v) => !v).length;
    final partsTrue = _partVerdicts.values.where((v) => v).length;
    final partsFalse = _partVerdicts.values.where((v) => !v).length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit review?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Panels confirmed damaged: $confirmed'),
            Text('Panels marked not damaged: $rejected'),
            if (_partVerdicts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Parts confirmed needed: $partsTrue'),
              Text('Parts marked not needed: $partsFalse'),
            ],
            const SizedBox(height: 12),
            const Text(
              'This cannot be changed after submitting.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await LearningRepository(Supabase.instance.client).saveReviews(
        submissionId: widget.args.submissionId,
        panels: widget.args.panels,
        panelVerdicts: _panelVerdicts,
        partVerdicts: _partVerdicts,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review saved. Thank you.')),
      );
      context.go('/');
    } catch (e) {
      setState(() => _message = 'Could not save review: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panels = widget.args.panels;
    final complete = _answeredItems == _totalItems;

    return Scaffold(
      backgroundColor: AppColors.workspaceLight,
      appBar: AppBar(title: const Text('Review AI result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('$_answeredItems of $_totalItems answered'),
          const SizedBox(height: 12),
          for (final p in panels) ...[
            _PanelCard(
              panel: p,
              panelVerdict: _panelVerdicts[p.name],
              partVerdict: (part) => _partVerdicts[partKey(p.name, part)],
              onPanel: (v) => setState(() => _panelVerdicts[p.name] = v),
              onPart: (part, v) => setState(
                () => _partVerdicts[partKey(p.name, part)] = v,
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: (!complete || _busy) ? null : _save,
            child: const Text('Submit review'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                style: const TextStyle(color: AppColors.fireRed),
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.panel,
    required this.panelVerdict,
    required this.partVerdict,
    required this.onPanel,
    required this.onPart,
  });

  final LearningPanel panel;
  final bool? panelVerdict;
  final bool? Function(String part) partVerdict;
  final ValueChanged<bool> onPanel;
  final void Function(String part, bool verdict) onPart;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              panel.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (panel.severity != null) Text('AI severity: ${panel.severity}'),
            const SizedBox(height: 8),
            const Text('Is this panel damaged?'),
            TrueFalseToggle(value: panelVerdict, onChanged: onPanel),
            for (final part in panel.parts) ...[
              const Divider(height: 24),
              Text('${part.name} x${part.quantity}'),
              if (part.reason.isNotEmpty)
                Text(part.reason,
                    style: const TextStyle(color: AppColors.daysGray)),
              const SizedBox(height: 4),
              TrueFalseToggle(
                value: partVerdict(part.name),
                onChanged: (v) => onPart(part.name, v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TrueFalseToggle extends StatelessWidget {
  const TrueFalseToggle({super.key, required this.value, required this.onChanged});

  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      emptySelectionAllowed: true,
      segments: const [
        ButtonSegment(value: true, label: Text('True')),
        ButtonSegment(value: false, label: Text('False')),
      ],
      selected: value == null ? const <bool>{} : {value!},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
    );
  }
}
