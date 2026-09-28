part of '../master_admin_desktop.dart';

// ─── Shared micro-widgets ─────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final Color bgColor, fgColor;
  const _Chip(
      {required this.cs,
      required this.label,
      required this.bgColor,
      required this.fgColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fgColor)),
      );
}

class _KpiCard extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  final String label, value;
  final bool highlight;
  const _KpiCard(
      {required this.cs,
      required this.icon,
      required this.label,
      required this.value,
      this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color:
                      cs.onSurface.withValues(alpha: 0.06),
                  blurRadius: 6)
            ]),
        child: Row(children: [
          Icon(icon,
              size: 18,
              color: highlight
                  ? cs.primary
                  : cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant)),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: highlight
                        ? cs.primary
                        : cs.onSurface,
                    fontFamily: 'monospace')),
          ]),
        ]),
      );
}

class _TH extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final int flex;
  final bool right;
  const _TH(
      {required this.cs,
      required this.label,
      required this.flex,
      this.right = false});

  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5),
            textAlign:
                right ? TextAlign.right : TextAlign.left),
      );
}

class _PulseDot extends StatelessWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
      width: 8,
      height: 8,
      decoration:
          BoxDecoration(color: color, shape: BoxShape.circle));
}

// ── Admin valet fee editor ────────────────────────────────────────────────────

class _AdminValetFeeEditor extends StatefulWidget {
  final ColorScheme cs;
  const _AdminValetFeeEditor({required this.cs});

  @override
  State<_AdminValetFeeEditor> createState() => _AdminValetFeeEditorState();
}

class _AdminValetFeeEditorState extends State<_AdminValetFeeEditor> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client
          .from('app_settings').select('value')
          .eq('key', 'valet_fee_base').maybeSingle();
      if (res != null && mounted) {
        _ctrl.text = (res['value'] as num?)?.toInt().toString() ?? '50000';
      }
    } catch (e) {
      debugPrint('[ValetFeeAdmin] load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final fee = int.tryParse(_ctrl.text.trim().replaceAll('.', ''));
    if (fee == null || fee < 0) {
      setState(() => _error = 'Masukkan nominal valid (angka)');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await Supabase.instance.client.rpc('admin_set_valet_fee', params: {'p_fee': fee});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Biaya valet diset ke Rp $fee'),
              backgroundColor: Colors.green));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    if (_loading) return const SizedBox(height: 24, child: LinearProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.local_taxi_outlined, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('Biaya Jemput (Valet)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: cs.onSurface, fontSize: 13),
              decoration: InputDecoration(
                prefixText: 'Rp ',
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : ElevatedButton(onPressed: _save, child: const Text('Simpan')),
        ]),
        const SizedBox(height: 4),
        Text('Berlaku untuk semua booking jenis jemput (pickup).',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
