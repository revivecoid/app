import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum GateStatus { loading, signedOut, needsProfile, ready, error }

/// Tracks whether the current session can use the learning app:
/// signed in AND has a row in ai_learning_respondents.
/// Accounts created in the client app can also become respondents by
/// completing the profile step; they share the same auth.users row.
class LearningGate extends ChangeNotifier {
  LearningGate(this._client) {
    _sub = _client.auth.onAuthStateChange.listen((_) => refresh());
    refresh();
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _sub;
  GateStatus _status = GateStatus.loading;

  GateStatus get status => _status;

  Future<void> refresh() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _set(GateStatus.signedOut);
      return;
    }
    try {
      final row = await _client
          .from('ai_learning_respondents')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      _set(row == null ? GateStatus.needsProfile : GateStatus.ready);
    } catch (_) {
      _set(GateStatus.error);
    }
  }

  void _set(GateStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// App-wide gate. Created lazily on first access, which happens after
/// Supabase.initialize in main_ai_learning.dart.
final LearningGate learningGate = LearningGate(Supabase.instance.client);
