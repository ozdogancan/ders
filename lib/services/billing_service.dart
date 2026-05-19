// Billing service — wraps RevenueCat (purchases_flutter) for Android Play Billing.
//
// IMPORTANT — OWNER SETUP REQUIRED:
//   1. Create a RevenueCat account at https://app.revenuecat.com
//   2. Add a new app → Android → upload Google Play service account JSON.
//   3. Create products in Play Console:
//        - koala_pro_weekly_v1   (₺149,99 / week)
//        - koala_pro_monthly_v1  (₺249,99 / month, 7-day trial)
//        - koala_pro_yearly_v1   (₺999,99 / year, 7-day trial)
//   4. In RevenueCat, create entitlement "pro" and attach all three products.
//   5. Create offering "default" with packages: weekly, monthly, yearly.
//   6. Copy the Android public SDK key from RevenueCat dashboard.
//   7. Replace the placeholder REVENUECAT_PUBLIC_KEY below (or pass via
//      --dart-define=REVENUECAT_KEY=... in build_android.ps1).
//
// Web is not supported by purchases_flutter — initialize() is a no-op on web.
// iOS is deferred to v2 (App Store products + RevenueCat iOS key).
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/config/env.dart';

class BillingService {
  BillingService._();

  // Replace via --dart-define=REVENUECAT_ANDROID_KEY=goog_xxxx at build time.
  static const String _publicKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: 'YOUR_REVENUECAT_PUBLIC_KEY',
  );

  static bool _initialized = false;

  /// Returns true if billing is supported on this platform/env.
  static bool get isSupported {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return true;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    if (!isSupported) {
      debugPrint('[billing] skipping init (web or non-Android)');
      return;
    }
    if (_publicKey == 'YOUR_REVENUECAT_PUBLIC_KEY') {
      debugPrint('[billing] REVENUECAT_ANDROID_KEY not configured — purchases disabled');
      return;
    }
    try {
      await Purchases.setLogLevel(LogLevel.warn);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final config = PurchasesConfiguration(_publicKey);
      if (uid != null) {
        config.appUserID = uid;
      }
      await Purchases.configure(config);
      _initialized = true;
      debugPrint('[billing] RevenueCat configured (uid=${uid ?? "anon"})');
    } catch (e) {
      debugPrint('[billing] init failed: $e');
    }
  }

  /// Re-identify on auth change (call from auth listener after sign-in).
  static Future<void> identify(String uid) async {
    if (!_initialized) return;
    try {
      await Purchases.logIn(uid);
    } catch (e) {
      debugPrint('[billing] identify failed: $e');
    }
  }

  static Future<void> logout() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('[billing] logout failed: $e');
    }
  }

  /// Returns the offering's available packages (weekly/monthly/yearly).
  static Future<List<Package>> getOfferings() async {
    if (!_initialized) return const [];
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return const [];
      return current.availablePackages;
    } catch (e) {
      debugPrint('[billing] getOfferings failed: $e');
      return const [];
    }
  }

  /// Purchase a package, then verify with backend. Returns true on success.
  static Future<bool> purchase(Package pkg) async {
    if (!_initialized) return false;
    try {
      final result = await Purchases.purchasePackage(pkg);
      // RevenueCat already grants entitlement client-side. Verify with our backend
      // so we have authoritative proUntil in Supabase.
      final productId = pkg.storeProduct.identifier;
      final entitlement = result.customerInfo.entitlements.active['pro'];
      if (entitlement == null) {
        debugPrint('[billing] purchase ok but no pro entitlement');
        return false;
      }
      // RevenueCat doesn't expose the raw Play purchaseToken on the entitlement.
      // The backend will fetch the Play API state; pass entitlement identifier
      // as a tracer. Webhook (RTDN) is the authoritative path; this is best-effort.
      await _verifyWithBackend(
        productId: productId,
        purchaseToken: entitlement.productIdentifier,
      );
      return true;
    } on PlatformException catch (e) {
      debugPrint('[billing] purchase failed: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[billing] purchase failed: $e');
      return false;
    }
  }

  /// Restore prior purchases (e.g. after reinstall).
  static Future<bool> restorePurchases() async {
    if (!_initialized) return false;
    try {
      await Purchases.restorePurchases();
      // Tell our backend to re-grant from history.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _restoreWithBackend(uid);
      }
      return true;
    } catch (e) {
      debugPrint('[billing] restore failed: $e');
      return false;
    }
  }

  /// Stream of customer info updates (entitlement changes).
  static Stream<CustomerInfo> get customerInfoStream {
    if (!_initialized || !isSupported) return const Stream.empty();
    final controller = StreamController<CustomerInfo>.broadcast();
    Purchases.addCustomerInfoUpdateListener(controller.add);
    return controller.stream;
  }

  static Future<void> _verifyWithBackend({
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      final res = await http.post(
        Uri.parse('${Env.koalaApiUrl}/api/billing/verify'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'platform': 'android',
          'productId': productId,
          'purchaseToken': purchaseToken,
          'userId': user.uid,
        }),
      );
      if (res.statusCode != 200) {
        debugPrint('[billing] backend verify ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[billing] backend verify error: $e');
    }
  }

  static Future<void> _restoreWithBackend(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      await http.post(
        Uri.parse('${Env.koalaApiUrl}/api/billing/restore'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'userId': uid}),
      );
    } catch (e) {
      debugPrint('[billing] backend restore error: $e');
    }
  }
}
