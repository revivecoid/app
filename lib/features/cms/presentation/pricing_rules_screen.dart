import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/rev_app_bar.dart';
import '../../../core/widgets/responsive_layout_guard.dart';
import '../../shared/services/pricing_matrix.dart';

// ─── Data Model ───────────────────────────────────────────────────────────────

class _PricingItem {
  final String key;
  final String label;
  double basePrice;
  double sedangMultiplier;
  double beratMultiplier;

  _PricingItem({
    required this.key,
    required this.label,
    required this.basePrice,
    this.sedangMultiplier = 1.5, // ignore: unused_element_parameter
    this.beratMultiplier = 2.0,  // ignore: unused_element_parameter
  });

  double get sedangPrice => basePrice * sedangMultiplier;
  double get beratPrice => basePrice * beratMultiplier;

  Map<String, dynamic> toMap() => {
        'panel_id': key,
        'panel_name': label,
        'base_rate': basePrice,
        'severity_min': sedangMultiplier,
        'severity_max': beratMultiplier,
      };
}

class _Section {
  final String title;
  final List<_PricingItem> items;
  const _Section({required this.title, required this.items});
}

// ─── Default Data ─────────────────────────────────────────────────────────────

List<_Section> _defaultSections() => [
      _Section(title: 'Depan', items: [
        _PricingItem(key: 'bumper_depan', label: 'Bumper Depan', basePrice: 500500),
        _PricingItem(key: 'spoiler_bumper_depan', label: 'Spoiler Bumper depan', basePrice: 286000),
        _PricingItem(key: 'kap_mesin', label: 'Kap Mesin', basePrice: 715000),
      ]),
      _Section(title: 'Belakang', items: [
        _PricingItem(key: 'bumper_belakang', label: 'Bumper Belakang', basePrice: 500500),
        _PricingItem(key: 'spoiler_bumper_belakang', label: 'Spoiler Bumper Belakang', basePrice: 286000),
        _PricingItem(key: 'bagasi', label: 'Bagasi', basePrice: 643500),
        _PricingItem(key: 'spoiler_bagasi', label: 'Spoiler Bagasi', basePrice: 286000),
      ]),
      _Section(title: 'Sisi Kanan (RH)', items: [
        _PricingItem(key: 'fender_rh', label: 'Fender RH', basePrice: 572000),
        _PricingItem(key: 'pintu_depan_rh', label: 'Pintu Depan RH', basePrice: 572000),
        _PricingItem(key: 'spion_rh', label: 'Spion RH', basePrice: 143000),
        _PricingItem(key: 'pintu_belakang_rh', label: 'Pintu Belakang RH', basePrice: 572000),
        _PricingItem(key: 'quarter_rh', label: 'Quarter RH', basePrice: 572000),
        _PricingItem(key: 'trisplang_rh', label: 'Trisplang RH', basePrice: 357500),
        _PricingItem(key: 'side_roof_rh', label: 'Side Roof RH', basePrice: 357500),
      ]),
      _Section(title: 'Sisi Kiri (LH)', items: [
        _PricingItem(key: 'fender_lh', label: 'Fender LH', basePrice: 572000),
        _PricingItem(key: 'pintu_depan_lh', label: 'Pintu Depan LH', basePrice: 572000),
        _PricingItem(key: 'spion_lh', label: 'Spion LH', basePrice: 143000),
        _PricingItem(key: 'pintu_belakang_lh', label: 'Pintu Belakang LH', basePrice: 572000),
        _PricingItem(key: 'quarter_lh', label: 'Quarter LH', basePrice: 572000),
        _PricingItem(key: 'trisplang_lh', label: 'Trisplang LH', basePrice: 357500),
        _PricingItem(key: 'side_roof_lh', label: 'Side Roof LH', basePrice: 357500),
      ]),
      _Section(title: 'Atap', items: [
        _PricingItem(key: 'roof', label: 'Roof', basePrice: 1001000),
      ]),
      _Section(title: 'Lainnya', items: [
        _PricingItem(key: 'cover', label: 'Cover', basePrice: 286000),
      ]),
    ];

// ─── Formatter ────────────────────────────────────────────────────────────────

String _fmtRp(double v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  int count = 0;
  for (int i = s.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write(',');
    buf.write(s[i]);
    count++;
  }
  return 'Rp ${buf.toString().split('').reversed.join()}';
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class PricingRulesScreen extends StatefulWidget {
  const PricingRulesScreen({super.key});

  @override
  State<PricingRulesScreen> createState() => _PricingRulesScreenState();
}

class _PricingRulesScreenState extends State<PricingRulesScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDirty = false;
  String? _errorMsg;
  late List<_Section> _sections;

  String? _editingKey;
  final Map<String, TextEditingController> _baseCtrl = {};
  final Map<String, TextEditingController> _sedangCtrl = {};
  final Map<String, TextEditingController> _beratCtrl = {};

  late final AnimationController _pulseAnim;
  late final Animation<double> _pulse;

  static const _tableName = 'pricing_rules';

  @override
  void initState() {
    super.initState();
    _sections = _defaultSections();
    _pulseAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _pulseAnim, curve: Curves.easeInOut));
    _fetchPricingRules();
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    for (final c in _baseCtrl.values) { c.dispose(); }
    for (final c in _sedangCtrl.values) { c.dispose(); }
    for (final c in _beratCtrl.values) { c.dispose(); }
    super.dispose();
  }

  // ── Supabase ──────────────────────────────────────────────────────────────

  Future<void> _fetchPricingRules() async {
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final rows = await Supabase.instance.client
          .from(_tableName)
          .select()
          .order('panel_id');
      final sections = _defaultSections();
      if (rows.isNotEmpty) {
        // Key DB rows by panel_id to match _PricingItem.key
        final Map<String, Map<String, dynamic>> byKey = {
          for (final r in (rows as List)) r['panel_id'] as String: r
        };
        for (final sec in sections) {
          for (final item in sec.items) {
            if (byKey.containsKey(item.key)) {
              final r = byKey[item.key]!;
              item.basePrice = (r['base_rate'] as num).toDouble();
              // severity_min = sedang multiplier, severity_max = berat multiplier
              item.sedangMultiplier =
                  (r['severity_min'] as num?)?.toDouble() ?? 1.5;
              item.beratMultiplier =
                  (r['severity_max'] as num?)?.toDouble() ?? 2.0;
            }
          }
        }
      }
      setState(() { _sections = sections; _isLoading = false; _isDirty = false; });
    } catch (e) {
      debugPrint('PricingRules fetch: $e');
      setState(() { _isLoading = false; _errorMsg = 'Gagal memuat data: $e'; });
    }
  }

  Future<void> _saveAll() async {
    if (_isSaving) return;
    setState(_commitActiveEdit);
    setState(() => _isSaving = true);
    try {
      final rows = [
        for (final sec in _sections)
          for (final item in sec.items) item.toMap()
      ];
      await Supabase.instance.client
          .from(_tableName)
          .upsert(rows, onConflict: 'panel_id');
      // Bust the Dart-side PricingMatrix cache so the next AI estimate
      // uses the newly saved prices without requiring an app restart.
      PricingMatrix.invalidateCache();
      setState(() { _isSaving = false; _isDirty = false; });
      if (mounted) {
        final savedCs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Text('Pricing rules berhasil disimpan'),
          ]),
          backgroundColor: savedCs.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      debugPrint('PricingRules save: $e');
      setState(() => _isSaving = false);
      if (mounted) {
        final errCs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: errCs.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Edit helpers ──────────────────────────────────────────────────────────

  void _startEdit(_PricingItem item) {
    _commitActiveEdit();
    setState(() {
      _editingKey = item.key;
      _baseCtrl[item.key] =
          TextEditingController(text: item.basePrice.toStringAsFixed(0));
      _sedangCtrl[item.key] =
          TextEditingController(text: item.sedangMultiplier.toString());
      _beratCtrl[item.key] =
          TextEditingController(text: item.beratMultiplier.toString());
    });
  }

  void _commitActiveEdit() {
    final key = _editingKey;
    if (key == null) return;
    for (final sec in _sections) {
      for (final item in sec.items) {
        if (item.key == key) {
          final base = double.tryParse(_baseCtrl[key]?.text ?? '');
          final sed = double.tryParse(_sedangCtrl[key]?.text ?? '');
          final ber = double.tryParse(_beratCtrl[key]?.text ?? '');
          if (base != null) item.basePrice = math.max(0, base);
          if (sed != null) item.sedangMultiplier = math.max(1, sed);
          if (ber != null) item.beratMultiplier = math.max(1, ber);
          _isDirty = true;
        }
      }
    }
    _disposeEditControllers(key);
    _editingKey = null;
  }

  void _cancelEdit() {
    if (_editingKey == null) return;
    _disposeEditControllers(_editingKey!);
    setState(() => _editingKey = null);
  }

  void _disposeEditControllers(String key) {
    _baseCtrl[key]?.dispose(); _baseCtrl.remove(key);
    _sedangCtrl[key]?.dispose(); _sedangCtrl.remove(key);
    _beratCtrl[key]?.dispose(); _beratCtrl.remove(key);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget body;
    if (_isLoading) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: _pulse,
          child: Icon(Icons.price_change_outlined, size: 56, color: cs.primary),
        ),
        const SizedBox(height: 16),
        Text('Memuat tabel harga…', style: theme.textTheme.bodyLarge),
      ]));
    } else if (_errorMsg != null) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: cs.error),
        const SizedBox(height: 12),
        Text(_errorMsg!, style: TextStyle(color: cs.error)),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _fetchPricingRules,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi')),
      ]));
    } else {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () { if (_editingKey != null) setState(_commitActiveEdit); },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme, cs),
              const SizedBox(height: 24),
              _buildLegend(theme, cs),
              const SizedBox(height: 28),
              for (final s in _sections) _buildSectionCard(s, theme, cs),
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const ReVAppBar(),
      body: ResponsiveLayoutGuard(
        mobileWidget: body,
        desktopWidget: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData t, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.price_change_outlined, size: 14, color: cs.onPrimaryContainer),
                const SizedBox(width: 6),
                Text('CMS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                        letterSpacing: 1)),
              ]),
            ),
            const SizedBox(height: 10),
            Text('Pricing Rules',
                style: t.textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Atur harga dasar (Ringan) per panel kendaraan. '
              'Sedang dan Berat dihitung otomatis dari multiplier — '
              'semua dapat diubah per-baris.',
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (_isDirty)
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Opacity(
                opacity: _pulse.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.tertiary.withValues(alpha: 0.6)),
                  ),
                  child: Row(children: [
                    Icon(Icons.edit_note, size: 14, color: cs.tertiary),
                    const SizedBox(width: 5),
                    Text('Ada perubahan belum disimpan',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onTertiaryContainer,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _fetchPricingRules,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reset'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _isDirty && !_isSaving ? _saveAll : null,
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 16),
              label: Text(_isSaving ? 'Menyimpan…' : 'Simpan Semua'),
            ),
          ]),
        ]),
      ],
    );
  }

  Widget _buildLegend(ThemeData t, ColorScheme cs, Color sedangColor, Color beratColor) {
    final items = [
      ('Ringan', '× 1.0  –  Harga Dasar',            cs.onSurfaceVariant),
      ('Sedang', '× 1.5  –  dapat diubah per baris', sedangColor),
      ('Berat',  '× 2.0  –  dapat diubah per baris', beratColor),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('Tingkat Keparahan:',
                style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          ]),
          for (final item in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: item.$3, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                Text(item.$1,
                    style: t.textTheme.labelSmall?.copyWith(
                        color: cs.onSurface, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Text('— ${item.$2}',
                    style: t.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant)),
              ]),
            ),
        ],
      ),
    );
  }


  Widget _buildSectionCard(
    _Section section, ThemeData t, ColorScheme cs, bool isDark,
    Color sedangColor, Color beratColor, Color ringanColor,
  ) {
    // Divider color — 5% white in dark, subtle outlineVariant in light
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : cs.outlineVariant.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: cs.shadow.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: isDark ? 8 : 16,
                offset: const Offset(0, 2))
          ],
          border: Border.all(
            color: isDark
                ? cs.outlineVariant.withValues(alpha: 0.15)
                : cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // ── Section header bar ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                border: Border(
                    bottom: BorderSide(
                        color: dividerColor, width: 1))),
            child: Row(children: [
              Icon(Icons.directions_car_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 10),
              Text(section.title,
                  style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${section.items.length} panel',
                    style: t.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),

          // ── Column headers ─────────────────────────────────────────────────
          Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              Expanded(flex: 3,
                child: Text('Panel',
                    style: t.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant, fontWeight: FontWeight.w700,
                        letterSpacing: 0.6))),
              Expanded(flex: 2,
                child: Row(children: [
                  Container(width: 7, height: 7,
                      decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 5),
                  Text('Ringan (Dasar)',
                      style: t.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant, fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ])),
              Expanded(flex: 2,
                child: Row(children: [
                  Container(width: 7, height: 7,
                      decoration: BoxDecoration(color: sedangColor,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 5),
                  Text('Sedang',
                      style: t.textTheme.labelSmall?.copyWith(
                          color: sedangColor, fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ])),
              Expanded(flex: 2,
                child: Row(children: [
                  Container(width: 7, height: 7,
                      decoration: BoxDecoration(color: beratColor,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 5),
                  Text('Berat',
                      style: t.textTheme.labelSmall?.copyWith(
                          color: beratColor, fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ])),
              const Expanded(flex: 1, child: SizedBox()),
            ]),
          ),

          // ── Data rows ──────────────────────────────────────────────────────
          for (int i = 0; i < section.items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: dividerColor, indent: 0, endIndent: 0),
            _buildRow(section.items[i], t, cs, sedangColor, beratColor, ringanColor),
          ],
        ]),
      ),
    );
  }

  Widget _buildRow(
    _PricingItem item, ThemeData t, ColorScheme cs,
    Color sedangColor, Color beratColor, Color ringanColor,
  ) {
    final isEditing = _editingKey == item.key;
    return Material(
      color: isEditing
          ? cs.primaryContainer.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: isEditing ? null : () => _startEdit(item),
        hoverColor: cs.surfaceContainerLow.withValues(alpha: 0.7),
        splashColor: cs.primaryContainer.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Panel name
            Expanded(
              flex: 3,
              child: Text(item.label,
                  style: t.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500, color: cs.onSurface)),
            ),
            // Ringan (neutral base)
            Expanded(
              flex: 2,
              child: isEditing
                  ? _NumField(
                      controller: _baseCtrl[item.key]!,
                      color: ringanColor,
                      prefix: 'Rp ',
                      digitsOnly: true,
                      onChanged: (_) => setState(() => _isDirty = true),
                    )
                  : _PriceCell(value: item.basePrice, color: ringanColor),
            ),
            // Sedang
            Expanded(
              flex: 2,
              child: isEditing
                  ? _MultiplierField(
                      controller: _sedangCtrl[item.key]!,
                      basePrice: item.basePrice,
                      color: sedangColor,
                      onChanged: (_) => setState(() => _isDirty = true),
                    )
                  : _PriceCell(
                      value: item.sedangPrice,
                      color: sedangColor,
                      multiplier: item.sedangMultiplier),
            ),
            // Berat
            Expanded(
              flex: 2,
              child: isEditing
                  ? _MultiplierField(
                      controller: _beratCtrl[item.key]!,
                      basePrice: item.basePrice,
                      color: beratColor,
                      onChanged: (_) => setState(() => _isDirty = true),
                    )
                  : _PriceCell(
                      value: item.beratPrice,
                      color: beratColor,
                      multiplier: item.beratMultiplier),
            ),
            // Action
            Expanded(
              flex: 1,
              child: isEditing
                  ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      IconButton(
                        tooltip: 'Batalkan',
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 18),
                        onPressed: _cancelEdit,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: 'Terapkan',
                        icon: Icon(Icons.check, color: cs.primary, size: 18),
                        onPressed: () => setState(_commitActiveEdit),
                        visualDensity: VisualDensity.compact,
                      ),
                    ])
                  : Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Edit harga',
                        icon: Icon(Icons.edit_outlined,
                            size: 16, color: cs.onSurfaceVariant),
                        onPressed: () => _startEdit(item),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Shared Sub-widgets ───────────────────────────────────────────────────────

class _PriceCell extends StatelessWidget {
  final double value;
  final Color color;
  final double? multiplier;
  const _PriceCell({required this.value, required this.color, this.multiplier});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _fmtRp(value),
          style: t.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: [const FontFeature.tabularFigures()]),
        ),
        if (multiplier != null && multiplier != 1.0)
          Text('× $multiplier',
              style: t.textTheme.labelSmall?.copyWith(
                  color: color.withValues(alpha: 0.55), fontSize: 10)),
      ],
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final Color color;
  final String prefix;
  final bool digitsOnly;
  final ValueChanged<String>? onChanged;
  const _NumField({
    required this.controller,
    required this.color,
    required this.prefix,
    required this.digitsOnly,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: digitsOnly
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: digitsOnly
            ? [FilteringTextInputFormatter.digitsOnly]
            : [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()]),
        decoration: InputDecoration(
          prefixText: prefix,
          prefixStyle: TextStyle(fontSize: 11, color: color),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          filled: true,
          fillColor: color.withValues(alpha: 0.06),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: color, width: 1.5)),
          isDense: true,
        ),
      ),
    );
  }
}

class _MultiplierField extends StatefulWidget {
  final TextEditingController controller;
  final double basePrice;
  final Color color;
  final ValueChanged<String>? onChanged;
  const _MultiplierField({
    required this.controller,
    required this.basePrice,
    required this.color,
    this.onChanged,
  });

  @override
  State<_MultiplierField> createState() => _MultiplierFieldState();
}

class _MultiplierFieldState extends State<_MultiplierField> {
  double _computed = 0;

  @override
  void initState() {
    super.initState();
    _recompute(widget.controller.text);
    widget.controller.addListener(() {
      if (mounted) _recompute(widget.controller.text);
    });
  }

  void _recompute(String v) {
    final m = double.tryParse(v) ?? 1.0;
    setState(() => _computed = widget.basePrice * m);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Text('×',
              style: TextStyle(
                  color: widget.color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          SizedBox(
            width: 52,
            height: 30,
            child: TextField(
              controller: widget.controller,
              onChanged: widget.onChanged,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
              ],
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.color),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                filled: true,
                fillColor: widget.color.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: widget.color.withValues(alpha: 0.3))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: widget.color.withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: widget.color, width: 1.5)),
                isDense: true,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 2),
        Text(_fmtRp(_computed),
            style: t.textTheme.labelSmall?.copyWith(
                color: widget.color.withValues(alpha: 0.7), fontSize: 10)),
      ],
    );
  }
}
