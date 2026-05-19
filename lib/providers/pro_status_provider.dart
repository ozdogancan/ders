// Pro status provider — fetches subscription state from /api/billing/status
// and reacts to RevenueCat customerInfo updates.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../services/billing_service.dart';

class ProStatus {
  const ProStatus({
    required this.isPro,
    this.proUntil,
    this.plan,
    this.platform,
    this.gracePeriod = false,
  });

  final bool isPro;
  final DateTime? proUntil;
  final String? plan;        // weekly | monthly | yearly
  final String? platform;    // android | ios | web
  final bool gracePeriod;

  static const ProStatus free = ProStatus(isPro: false);

  factory ProStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }
    return ProStatus(
      isPro: json['isPro'] == true,
      proUntil: parse(json['proUntil']),
      plan: json['plan'] as String?,
      platform: json['platform'] as String?,
      gracePeriod: json['gracePeriod'] == true,
    );
  }
}

class ProStatusNotifier extends AsyncNotifier<ProStatus> {
  StreamSubscription<dynamic>? _customerInfoSub;

  @override
  Future<ProStatus> build() async {
    // Listen to RevenueCat customer info → invalidate this provider.
    _customerInfoSub ??= BillingService.customerInfoStream.listen((_) {
      // Defer to next tick; ref.invalidateSelf() schedules a rebuild.
      Future.microtask(() {
        if (ref.mounted) ref.invalidateSelf();
      });
    });
    ref.onDispose(() {
      _customerInfoSub?.cancel();
      _customerInfoSub = null;
    });

    return _fetch();
  }

  Future<ProStatus> _fetch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return ProStatus.free;
    try {
      final idToken = await user.getIdToken();
      final res = await http.get(
        Uri.parse('${Env.koalaApiUrl}/api/billing/status'),
        headers: {
          if (idToken != null) 'Authorization': 'Bearer $idToken',
          'X-User-Id': user.uid,
        },
      );
      if (res.statusCode != 200) {
        debugPrint('[pro_status] ${res.statusCode}: ${res.body}');
        return ProStatus.free;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return ProStatus.fromJson(json);
    } catch (e) {
      debugPrint('[pro_status] fetch error: $e');
      return ProStatus.free;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

final proStatusProvider =
    AsyncNotifierProvider<ProStatusNotifier, ProStatus>(ProStatusNotifier.new);
