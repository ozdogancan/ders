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

  /// AI'in ürettiği after görseli yükle. data: URL veya raw bytes alır.
  /// Vercel Blob upload başarısız olduğunda Gemini batch'inden gelen base64
  /// data URL'i normal https URL'e çevirmek için kullanılır.
  static Future<String?> uploadAfterFromDataUrl(String dataUrl) async {
    try {
      if (!dataUrl.startsWith('data:')) return dataUrl; // zaten URL
      final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(dataUrl);
      if (match == null) return null;
      final b64 = match.group(2)!;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final res = await http
          .post(
            Uri.parse('${Env.koalaApiUrl}/api/upload-image'),
            headers: {
              ...await AuthTokenService.authHeaders(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'bytes_b64': b64,
              'kind': 'after',
              'userId': uid,
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) {
        debugPrint('[UploadService] uploadAfter HTTP ${res.statusCode}');
        return null;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return j['url']?.toString();
    } catch (e) {
      debugPrint('[UploadService] uploadAfter error: $e');
      return null;
    }
  }

  static Uint8List _optimize(Uint8List input) {
    try {
      final decoded = img.decodeImage(input);
      if (decoded == null) return input;
      // Before image kalite artırımı: 1024/q72 → 1600/q85.
      // Projelerim detail before/after slider'ında pixelated görünüyordu.
      const maxEdge = 1600;
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
      return Uint8List.fromList(img.encodeJpg(scaled, quality: 85));
    } catch (_) {
      return input;
    }
  }
}
