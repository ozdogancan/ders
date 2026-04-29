import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import 'auth_token_service.dart';

/// Tasarım feedback servisi — koala-api/api/feedback üzerinden Supabase
/// design_feedback tablosuna upsert. Anonymous user'lar gönderemez.
class FeedbackService {
  FeedbackService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> submit({
    required String designId,
    required bool liked,
    String? room,
    String? theme,
    String? palette,
    String? layout,
    String? afterUrl,
    Map<String, dynamic>? extraData,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final res = await http
          .post(
            Uri.parse('${Env.koalaApiUrl}/api/feedback'),
            headers: {
              ...await AuthTokenService.authHeaders(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'userId': uid,
              'designId': designId,
              'rating': liked ? 'like' : 'dislike',
              if (room != null) 'room': room,
              if (theme != null) 'theme': theme,
              if (palette != null) 'palette': palette,
              if (layout != null) 'layout': layout,
              if (afterUrl != null) 'afterUrl': afterUrl,
              if (extraData != null) 'extraData': extraData,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 400) {
        debugPrint('FeedbackService non-200: ${res.statusCode} ${res.body}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('FeedbackService error: $e');
      return false;
    }
  }
}
