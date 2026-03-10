import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/env.dart';

class SupabaseStorageService {
  SupabaseStorageService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  /// Web-uyumlu: Uint8List ile fotograf upload
  Future<String> uploadQuestionImageBytes({
    required Uint8List bytes,
    required String userId,
  }) async {
    if (!Env.hasSupabaseConfig) {
      throw StateError(
        'Supabase config missing. Add SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }

    final String filePath = 'question_images/$userId/${const Uuid().v4()}.jpg';

    await _client.storage
        .from(Env.supabaseBucket)
        .uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );

    return _client.storage.from(Env.supabaseBucket).getPublicUrl(filePath);
  }

  Future<String> uploadAvatarBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!Env.hasSupabaseConfig) {
      throw StateError('Supabase config missing.');
    }
    final String filePath = 'avatars/$fileName';
    await _client.storage
        .from(Env.supabaseBucket)
        .uploadBinary(filePath, bytes,
            fileOptions:
                const FileOptions(contentType: 'image/png', upsert: true));
    return _client.storage.from(Env.supabaseBucket).getPublicUrl(filePath);
  }
}
