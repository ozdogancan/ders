import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class CreditService {
  static const String _creditKey = 'credit_balance_v1';
  static const int _defaultCredits = 10;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Get current credit balance
  Future<int> getCredits() async {
    // Try Supabase first
    if (_uid != null) {
      try {
        final data = await Supabase.instance.client
            .from('users')
            .select('credits')
            .eq('id', _uid!)
            .maybeSingle();
        if (data != null && data['credits'] != null) {
          final credits = data['credits'] as int;
          // Sync to SharedPreferences as cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_creditKey, credits);
          return credits;
        }
      } catch (_) {}
    }

    // Fallback to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_creditKey);
    if (value != null) return value;
    await prefs.setInt(_creditKey, _defaultCredits);
    return _defaultCredits;
  }

  /// Add credits (purchase)
  Future<int> addCredits(int amount) async {
    final current = await getCredits();
    final next = current + amount;

    // Update Supabase
    if (_uid != null) {
      try {
        await Supabase.instance.client
            .from('users')
            .update({
              'credits': next,
              'total_credits_purchased': current + amount,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _uid!);

        // Log transaction
        await Supabase.instance.client.from('credit_transactions').insert({
          'user_id': _uid!,
          'amount': amount,
          'type': 'purchase',
          'source': 'credit_store',
          'balance_after': next,
        });
      } catch (_) {}
    }

    // Update SharedPreferences cache
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_creditKey, next);
    return next;
  }

  /// Spend credits
  Future<int> spendCredits(int amount) async {
    final current = await getCredits();
    if (current < amount) {
      throw StateError('Insufficient credit');
    }
    final next = current - amount;

    // Update Supabase
    if (_uid != null) {
      try {
        await Supabase.instance.client
            .from('users')
            .update({
              'credits': next,
              'total_credits_spent': (current - next),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _uid!);

        // Log transaction
        await Supabase.instance.client.from('credit_transactions').insert({
          'user_id': _uid!,
          'amount': -amount,
          'type': 'spend',
          'source': 'question_solve',
          'balance_after': next,
        });
      } catch (_) {}
    }

    // Update SharedPreferences cache
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_creditKey, next);
    return next;
  }

  /// Spend one credit (convenience)
  Future<int> spendOneCredit() async {
    return spendCredits(1);
  }

  /// Refund one credit (AI error)
  Future<int> refundOneCredit() async {
    final current = await getCredits();
    final next = current + 1;
    if (_uid != null) {
      try {
        await Supabase.instance.client
            .from('users')
            .update({
              'credits': next,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _uid!);
        await Supabase.instance.client.from('credit_transactions').insert({
          'user_id': _uid!,
          'amount': 1,
          'type': 'refund',
          'source': 'ai_error',
          'balance_after': next,
        });
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('credit_balance_v1', next);
    return next;
  }
}


