import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../core/config/env.dart';
import 'auth_token_service.dart';

class UploadService {
  UploadService._();

  /// Bytes'ı 1024px JPG q72'ye optimize et + koala-api/api/upload-image
  /// üzerinden Supabase storage'a yükle. Public URL döner. Hata: null.
  static Future<String?> uploadBefore(Uint8List bytes) async {
    try {
      final optimized = _optimize(bytes);
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final res = await http
          .post(
            Uri.parse('${Env.koalaApiUrl}/api/upload-image'),
            headers: {
              ...await AuthTokenService.authHeaders(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'bytes_b64': base64Encode(optimized),
              'kind': 'before',
              'userId': uid,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        debugPrint('[UploadService] HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return j['url']?.toString();
    } catch (e) {
      debugPrint('[UploadService] error: $e');
      return null;
    }
  }

  static Uint8List _optimize(Uint8List input) {
    try {
      final decoded = img.decodeImage(input);
      if (decoded == null) return input;
      const maxEdge = 1024;
      final w = decoded.width;
      final h = decoded.height;
      img.Image scaled = decoded;
      if (w > maxEdge || h > maxEdge) {
        if (w >= h) {
          scaled = img.copyResize(decoded, width: maxEdge);
        } else {
          scaled = img.copyResize(decoded, height: maxEdge);
        }
      }
      return Uint8List.fromList(img.encodeJpg(scaled, quality: 72));
    } catch (_) {
      return input;
    }
  }
}
