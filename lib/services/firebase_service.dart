import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';
import 'push_token_service.dart';

class FirebaseService {
  FirebaseService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  Future<void>? _googleInitFuture;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> _ensureGoogleInitialized() {
    return _googleInitFuture ??= _googleSignIn.initialize(
      clientId: Env.googleClientId.isEmpty ? null : Env.googleClientId,
      serverClientId: Env.googleServerClientId.isEmpty
          ? null
          : Env.googleServerClientId,
    );
  }

  Future<UserCredential> createAccountWithEmail({
    required String email,
    required String password,
  }) async {
    final UserCredential credential = await _auth
        .createUserWithEmailAndPassword(email: email, password: password);
    await _syncUserProfile(credential.user);
    return credential;
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final UserCredential credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _syncUserProfile(credential.user);
    return credential;
  }

  Future<UserCredential> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final GoogleSignInAccount account = await _googleSignIn.authenticate();
    final GoogleSignInAuthentication authData = account.authentication;

    if (authData.idToken == null || authData.idToken!.isEmpty) {
      throw StateError('Google Sign-In did not provide an ID token.');
    }

    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: authData.idToken,
    );
    final UserCredential userCredential = await _auth.signInWithCredential(
      credential,
    );
    await _syncUserProfile(userCredential.user);
    return userCredential;
  }

  Future<void> signOut() async {
    // FCM token sil
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await PushTokenService.removeToken(token);
      }
    } catch (e) {
      // Non-fatal: sign-out yine de devam eder, token eski kalırsa push gelmez.
      debugPrint('FirebaseService: FCM token cleanup on sign-out failed: $e');
    }

    await _auth.signOut();
    if (_googleInitFuture != null) {
      await _googleSignIn.signOut();
    }
  }

  Future<void> _syncUserProfile(User? user) async {
    if (user == null) {
      return;
    }

    // Firestore sync — never block login on transient errors
    try {
      await _firestore.collection('users').doc(user.uid).set(<String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoURL,
        'lastLoginAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore user profile sync error: $e');
    }

    // Supabase users tablosuna upsert (internal retry + try/catch)
    await _syncToSupabase(user);

    // Supabase client'a x-user-id header ekle (RLS için)
    // NOT: Firebase Auth + Supabase pattern — gelecekte custom JWT'ye geçilmeli
    if (Env.hasSupabaseConfig) {
      Supabase.instance.client.rest.headers['x-user-id'] = user.uid;
    }

    // FCM token kaydet
    await _registerFcmToken();
  }

  /// FCM token al ve Supabase'e kaydet
  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // İzin iste (iOS/web)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await messaging.getToken();
        if (token != null) {
          final platform = defaultTargetPlatform == TargetPlatform.iOS
              ? TokenPlatform.ios
              : defaultTargetPlatform == TargetPlatform.android
                  ? TokenPlatform.android
                  : TokenPlatform.web;

          await PushTokenService.registerToken(
            deviceToken: token,
            platform: platform,
          );
        }

        // Token yenilenince de kaydet
        messaging.onTokenRefresh.listen((newToken) {
          final platform = defaultTargetPlatform == TargetPlatform.iOS
              ? TokenPlatform.ios
              : defaultTargetPlatform == TargetPlatform.android
                  ? TokenPlatform.android
                  : TokenPlatform.web;
          PushTokenService.registerToken(
            deviceToken: newToken,
            platform: platform,
          );
        });
      }
    } catch (e) {
      debugPrint('FCM token registration error: $e');
    }
  }

  Future<void> _syncToSupabase(User user) async {
    if (!Env.hasSupabaseConfig) return;
    // Retry on transient ClientException (network hiccup during login)
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await Supabase.instance.client.from('users').upsert({
          'id': user.uid,
          'email': user.email,
          'display_name': user.displayName,
          'photo_url': user.photoURL,
          'last_login_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'id');
        return;
      } catch (e) {
        debugPrint('Supabase user sync attempt ${attempt + 1} failed: $e');
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
  }
}
