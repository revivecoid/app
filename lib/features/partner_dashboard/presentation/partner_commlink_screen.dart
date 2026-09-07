import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _primary = Color(0xFFa40016);
const _primaryContainer = Color(0xFFd10721);
const _onPrimary = Color(0xFFffffff);
const _emerald500 = Color(0xFF10B981);

// ─── Data model ───────────────────────────────────────────────────────────────
class _CommMessage {
  final String id;
  final String body;
  final bool fromAdmin;
  final bool isRead;
  final DateTime sentAt;
  const _CommMessage({
    required this.id,
    required this.body,
    required this.fromAdmin,
    required this.isRead,
    required this.sentAt,
  });

  factory _CommMessage.fromMap(Map<String, dynamic> map) => _CommMessage(
        id: map['id']?.toString() ?? '',
        body: map['body']?.toString() ?? '',
        fromAdmin: map['from_admin'] == true,
        isRead: map['is_read'] == true,
        sentAt: map['sent_at'] != null ? DateTime.tryParse(map['sent_at'].toString()) ?? DateTime.now() : DateTime.now(),
      );
}

// ─── State & notifier ─────────────────────────────────────────────────────────
class _CommLinkState {
  final List<_CommMessage> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;

  const _CommLinkState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
  });

  _CommLinkState copyWith({
    List<_CommMessage>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
  }) => _CommLinkState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isSending: isSending ?? this.isSending,
    error: error,
  );
}

class _CommLinkNotifier extends StateNotifier<_CommLinkState> {
  final String partnerId;

  _CommLinkNotifier(this.partnerId) : super(const _CommLinkState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await Supabase.instance.client
          .from('partner_messages')
          .select()
          .eq('partner_id', partnerId)
          .order('sent_at', ascending: true)
          .limit(100);

      final msgs = (response as List).map((m) => _CommMessage.fromMap(m as Map<String, dynamic>)).toList();

      // Mark unread admin messages as read
      final unreadIds = msgs.where((m) => m.fromAdmin && !m.isRead).map((m) => m.id).toList();
      if (unreadIds.isNotEmpty) {
        await Supabase.instance.client
            .from('partner_messages')
            .update({'is_read': true})
            .inFilter('id', unreadIds);
      }

      state = state.copyWith(messages: msgs, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load messages: $e');
    }
  }

  Future<void> sendMessage(String body) async {
    if (body.trim().isEmpty) return;
    state = state.copyWith(isSending: true, error: null);
    try {
      final response = await Supabase.instance.client
          .from('partner_messages')
          .insert({
            'partner_id': partnerId,
            'body': body.trim(),
            'from_admin': false,
            'is_read': false,
            'sent_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final newMsg = _CommMessage.fromMap(response as Map<String, dynamic>);
      state = state.copyWith(
        messages: [...state.messages, newMsg],
        isSending: false,
      );
    } catch (e) {
      state = state.copyWith(isSending: false, error: 'Failed to send: $e');
    }
  }
}

// ─── Provider factory ─────────────────────────────────────────────────────────
final _commLinkProvider = StateNotifierProvider.family<_CommLinkNotifier, _CommLinkState, String>(
  (ref, partnerId) => _CommLinkNotifier(partnerId),
);

// ─── Screen ───────────────────────────────────────────────────────────────────
class PartnerCommLinkScreen extends ConsumerStatefulWidget {
  const PartnerCommLinkScreen({super.key});

  @override
  ConsumerState<PartnerCommLinkScreen> createState() => _PartnerCommLinkScreenState();
}

class _PartnerCommLinkScreenState extends ConsumerState<PartnerCommLinkScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  String get _partnerId {
    final user = Supabase.instance.client.auth.currentUser;
    return user?.userMetadata?['partner_id']?.toString() ?? user?.id ?? '';
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pid = _partnerId;
    final state = ref.watch(_commLinkProvider(pid));
    final notifier = ref.read(_commLinkProvider(pid).notifier);
    final cs = Theme.of(context).colorScheme;

    ref.listen(_commLinkProvider(pid), (_, next) {
      if (next.messages.isNotEmpty) _scrollToBottom();
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.error!),
          backgroundColor: _primaryContainer,
        ));
      }
    });

    return LayoutBuilder(builder: (ctx, constraints) {
      final isDesktop = constraints.maxWidth > 900;

      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Sidebar ────────────────────────────────────────────────────
          _CommSidebar(isDesktop: isDesktop, cs: cs),

          // ── Main chat area ─────────────────────────────────────────────
          Expanded(child: Column(children: [
            // Header bar
            _CommHeader(isDesktop: isDesktop, onRefresh: notifier.load, cs: cs),

            // Messages
            Expanded(child: state.isLoading
              ? const Center(child: CircularProgressIndicator(color: _primary))
              : state.messages.isEmpty
                  ? _EmptyCommState(cs: cs)
                  : _MessageList(messages: state.messages, scrollCtrl: _scrollCtrl, cs: cs),
            ),

            // Composer
            _MessageComposer(
              ctrl: _msgCtrl,
              isSending: state.isSending,
              cs: cs,
              onSend: () async {
                final text = _msgCtrl.text;
                _msgCtrl.clear();
                await notifier.sendMessage(text);
              },
            ),
          ])),
        ]),
      );
    });
  }
}

// ─── Sidebar ──────────────────────────────────────────────────────────────────
class _CommSidebar extends StatelessWidget {
  final bool isDesktop;
  final ColorScheme cs;
  const _CommSidebar({required this.isDesktop, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isDesktop ? 272 : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      child: isDesktop ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Logo header
        Container(
          height: 64, padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHigh))),
          child: Row(children: [
            Container(width: 30, height: 30, decoration: const BoxDecoration(color: _primaryContainer, shape: BoxShape.circle), child: const Icon(Icons.build_circle, color: _onPrimary, size: 16)),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: const [
              Text('re-V', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.bold)),
              Text('OPS CORE', style: TextStyle(color: _primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ]),
          ]),
        ),
        // Nav items
        _SidebarItem(icon: Icons.view_kanban_outlined, label: 'Job Board / Pipeline', onTap: () => context.go('/partner-dashboard')),
        _SidebarItem(icon: Icons.calendar_month_outlined, label: 'Schedule Config', onTap: () => context.go('/partner-dashboard/schedule')),
        _SidebarItem(icon: Icons.speed_outlined, label: 'Quota & Panel Durations', onTap: () => context.go('/partner-dashboard/quota')),
        _SidebarItem(icon: Icons.storefront_outlined, label: 'My Profile', onTap: () => context.go('/partner-dashboard/profile')),
        _SidebarItem(icon: Icons.tune_outlined, label: 'Workshop Settings', onTap: () => context.go('/partner-dashboard/settings')),
        _SidebarItem(icon: Icons.forum_outlined, label: 'Commlink & Messages', isActive: true),
      ]) : const SizedBox.shrink(),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  const _SidebarItem({required this.icon, required this.label, this.isActive = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? _primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(icon, color: isActive ? const Color(0xFFFFE1DE) : Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: isActive ? const Color(0xFFFFE1DE) : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.w500))),
          ]),
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────
class _CommHeader extends StatelessWidget {
  final bool isDesktop;
  final VoidCallback onRefresh;
  final ColorScheme cs;
  const _CommHeader({required this.isDesktop, required this.onRefresh, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHigh)),
      ),
      child: Row(children: [
        if (!isDesktop) ...[
          IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant), onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 4),
        ],
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.support_agent_rounded, color: _primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: const [
          Text('Commlink — Admin Hotline', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('Secure channel with Revive Ops Core admin team', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(20), border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHigh)),
          child: Row(children: [
            Container(width: 7, height: 7, decoration: const BoxDecoration(color: _emerald500, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            const Text('ADMIN ONLINE', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(icon: const Icon(Icons.refresh_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20), tooltip: 'Refresh', onPressed: onRefresh),
      ]),
    );
  }
}

// ─── Message List ─────────────────────────────────────────────────────────────
class _MessageList extends StatelessWidget {
  final List<_CommMessage> messages;
  final ScrollController scrollCtrl;
  final ColorScheme cs;
  const _MessageList({required this.messages, required this.scrollCtrl, required this.cs});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[i];
        final isAdmin = msg.fromAdmin;
        final showDate = i == 0 ||
            messages[i].sentAt.day != messages[i - 1].sentAt.day;

        return Column(crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
          if (showDate) _DateDivider(date: msg.sentAt),
          _MessageBubble(msg: msg, isAdmin: isAdmin),
          const SizedBox(height: 4),
        ]);
      },
    );
  }
}

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String _label() {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        const Expanded(child: Divider(color: Theme.of(context).colorScheme.surfaceContainerHigh)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(_label(), style: const TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        const Expanded(child: Divider(color: Theme.of(context).colorScheme.surfaceContainerHigh)),
      ]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _CommMessage msg;
  final bool isAdmin;
  const _MessageBubble({required this.msg, required this.isAdmin});

  String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        bottom: 4,
        left: isAdmin ? 0 : 60,
        right: isAdmin ? 60 : 0,
      ),
      child: Row(
        mainAxisAlignment: isAdmin ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.support_agent_rounded, color: _primary, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: Column(
            crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              if (isAdmin)
                const Padding(
                  padding: EdgeInsets.only(bottom: 3, left: 2),
                  child: Text('Revive Admin', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isAdmin ? Theme.of(context).colorScheme.surfaceContainerHighest : _primaryContainer,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: isAdmin ? Radius.zero : const Radius.circular(12),
                    bottomRight: isAdmin ? const Radius.circular(12) : Radius.zero,
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))],
                  border: isAdmin ? Border.all(color: Theme.of(context).colorScheme.surfaceContainerHigh) : null,
                ),
                child: Text(msg.body, style: TextStyle(color: isAdmin ? Theme.of(context).colorScheme.onSurface : _onPrimary, fontSize: 13, height: 1.4)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 2, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_time(msg.sentAt), style: const TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
                    if (!isAdmin) ...[
                      const SizedBox(width: 4),
                      Icon(msg.isRead ? Icons.done_all_rounded : Icons.done_rounded, size: 13, color: msg.isRead ? _emerald500 : Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ],
                ),
              ),
            ],
          )),
          if (!isAdmin) ...[
            const SizedBox(width: 8),
            Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(color: _primaryContainer, shape: BoxShape.circle),
              child: const Icon(Icons.person_rounded, color: _onPrimary, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyCommState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyCommState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(color: _primary.withValues(alpha: 0.08), shape: BoxShape.circle),
        child: const Icon(Icons.forum_outlined, color: _primary, size: 36),
      ),
      const SizedBox(height: 16),
      const Text('No messages yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('Send a message to the Revive Ops admin team.\nThey typically respond within 1 business hour.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
    ]));
  }
}

// ─── Message Composer ─────────────────────────────────────────────────────────
class _MessageComposer extends StatelessWidget {
  final TextEditingController ctrl;
  final bool isSending;
  final VoidCallback onSend;
  final ColorScheme cs;
  const _MessageComposer({required this.ctrl, required this.isSending, required this.onSend, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHigh)),
      ),
      child: Row(children: [
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Theme.of(context).colorScheme.surfaceContainerHigh),
          ),
          child: TextField(
            controller: ctrl,
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'Type a message to admin…',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              border: InputBorder.none,
              isDense: true,
            ),
            style: const TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
          ),
        )),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: isSending ? null : onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isSending ? Theme.of(context).colorScheme.surfaceContainerHigh : _primaryContainer,
              shape: BoxShape.circle,
              boxShadow: isSending ? [] : [BoxShadow(color: _primaryContainer.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: isSending
                ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: _primary, strokeWidth: 2))
                : const Icon(Icons.send_rounded, color: _onPrimary, size: 20),
          ),
        ),
      ]),
    );
  }
}
