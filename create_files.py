# -*- coding: utf-8 -*-

# === SCAN STORE ===
scan_store = """import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../models/scan_analysis.dart';
import '../services/supabase_storage_service.dart';

enum ScanStatus { analyzing, completed, error }

class LocalScan {
  LocalScan({
    required this.id,
    required this.imageBytes,
    required this.scanType,
    required this.createdAt,
    this.status = ScanStatus.analyzing,
    this.analysis,
    this.imageUrl,
    this.isRead = false,
    this.isFavorite = false,
    this.chatMessages = const [],
  });

  final String id;
  Uint8List imageBytes;
  final String scanType;
  final DateTime createdAt;
  ScanStatus status;
  ScanAnalysis? analysis;
  String? imageUrl;
  bool isRead;
  bool isFavorite;
  List<ScanChat> chatMessages;
}

class ScanChat {
  ScanChat({required this.role, required this.text, DateTime? time})
      : time = time ?? DateTime.now();
  final String role;
  final String text;
  final DateTime time;
}

class ScanStore extends ChangeNotifier {
  ScanStore._();
  static final ScanStore instance = ScanStore._();

  final List<LocalScan> _scans = [];
  List<LocalScan> get scans => List.unmodifiable(_scans);

  bool _loaded = false;
  bool get loaded => _loaded;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  SupabaseClient get _sb => Supabase.instance.client;

  LocalScan? getById(String id) {
    for (final s in _scans) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _sortScans() {
    _scans.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> loadFromSupabase({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = false;
    final uid = _uid;
    if (uid == null) {
      debugPrint('ScanStore.load: No user, skipping.');
      _loaded = true;
      notifyListeners();
      return;
    }
    debugPrint('ScanStore.load: uid=\\$uid');
    _scans.clear();

    try {
      final rows = await _sb
          .from('scans')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      for (final row in rows) {
        final id = row['id'] as String;
        if (getById(id) != null) continue;

        final imageUrl = row['image_url'] as String?;
        Uint8List imageBytes = Uint8List(0);

        if (imageUrl != null && imageUrl.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(imageUrl));
            if (response.statusCode == 200) {
              imageBytes = response.bodyBytes;
            }
          } catch (e) {
            debugPrint('Image download failed for \\$id: \\$e');
          }
        }

        final statusStr = row['status'] as String? ?? 'analyzing';
        ScanStatus status;
        switch (statusStr) {
          case 'completed':
            status = ScanStatus.completed;
            break;
          case 'error':
            status = ScanStatus.error;
            break;
          default:
            status = ScanStatus.analyzing;
        }

        ScanAnalysis? analysis;
        final analysisJson = row['analysis'];
        if (analysisJson != null && analysisJson is Map<String, dynamic>) {
          try {
            analysis = ScanAnalysis.fromJson(analysisJson);
          } catch (e) {
            debugPrint('Analysis parse error: \\$e');
          }
        }

        _scans.add(LocalScan(
          id: id,
          imageBytes: imageBytes,
          scanType: row['scan_type'] as String? ?? 'room',
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
          status: status,
          analysis: analysis,
          imageUrl: imageUrl,
          isRead: row['is_read'] as bool? ?? false,
          isFavorite: row['is_favorite'] as bool? ?? false,
        ));
      }

      await _loadChats();
      _sortScans();
      _loaded = true;
      notifyListeners();
      debugPrint('ScanStore.load: \\${_scans.length} scans loaded.');
    } catch (e) {
      debugPrint('ScanStore.load error: \\$e');
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _loadChats() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('chat_messages')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: true);

      for (final row in rows) {
        final scanId = row['question_id'] as String?;
        if (scanId == null) continue;
        final scan = getById(scanId);
        if (scan == null) continue;
        scan.chatMessages = [
          ...scan.chatMessages,
          ScanChat(
            role: row['role'] as String? ?? 'ai',
            text: row['content'] as String? ?? '',
            time: DateTime.tryParse(row['created_at'] as String? ?? ''),
          ),
        ];
      }
    } catch (e) {
      debugPrint('Load scan chats error: \\$e');
    }
  }

  LocalScan add({required Uint8List imageBytes, String scanType = 'room', String? imageUrl}) {
    final scan = LocalScan(
      id: 'scan_\\${DateTime.now().millisecondsSinceEpoch}',
      imageBytes: imageBytes,
      scanType: scanType,
      createdAt: DateTime.now(),
      imageUrl: imageUrl,
    );
    _scans.insert(0, scan);
    notifyListeners();
    _uploadAndSave(scan, imageBytes);
    return scan;
  }

  Future<void> _uploadAndSave(LocalScan scan, Uint8List imageBytes) async {
    final uid = _uid;
    if (uid == null) {
      await _saveScanToDb(scan);
      return;
    }
    try {
      final storageService = SupabaseStorageService();
      final url = await storageService.uploadQuestionImageBytes(
        bytes: imageBytes,
        userId: uid,
      );
      scan.imageUrl = url;
      notifyListeners();
      await _saveScanToDb(scan);
    } catch (e) {
      debugPrint('Upload failed: \\$e');
      await _saveScanToDb(scan);
    }
  }

  void complete(String id, ScanAnalysis analysis, String rawResponse) {
    final scan = getById(id);
    if (scan == null) return;
    scan.status = ScanStatus.completed;
    scan.analysis = analysis;
    notifyListeners();
    _updateScanInDb(id, {
      'status': 'completed',
      'analysis': analysis.toJson(),
      'ai_raw_response': rawResponse,
    });
  }

  void setError(String id) {
    final scan = getById(id);
    if (scan == null) return;
    scan.status = ScanStatus.error;
    notifyListeners();
    _updateScanInDb(id, {'status': 'error'});
  }

  void toggleFavorite(String id) {
    final scan = getById(id);
    if (scan == null) return;
    scan.isFavorite = !scan.isFavorite;
    notifyListeners();
    _updateScanInDb(id, {'is_favorite': scan.isFavorite});
  }

  void markRead(String id) {
    final scan = getById(id);
    if (scan == null || scan.isRead) return;
    scan.isRead = true;
    notifyListeners();
    _updateScanInDb(id, {'is_read': true});
  }

  void remove(String id) {
    _scans.removeWhere((s) => s.id == id);
    notifyListeners();
    _deleteScanFromDb(id);
  }

  void addChat(String id, ScanChat msg) {
    final scan = getById(id);
    if (scan == null) return;
    scan.chatMessages = [...scan.chatMessages, msg];
    notifyListeners();
    _saveChatToDb(id, msg.role, msg.text);
  }

  Future<void> _saveScanToDb(LocalScan scan) async {
    if (_uid == null) return;
    try {
      await _sb.from('scans').insert({
        'id': scan.id,
        'user_id': _uid!,
        'scan_type': scan.scanType,
        'image_url': scan.imageUrl ?? '',
        'status': 'analyzing',
        'created_at': scan.createdAt.toIso8601String(),
        'is_read': false,
        'is_favorite': false,
        'partner': 'evlumba',
      });
    } catch (e) {
      debugPrint('Save scan error: \\$e');
    }
  }

  Future<void> _updateScanInDb(String id, Map<String, dynamic> fields) async {
    if (_uid == null) return;
    try {
      await _sb.from('scans').update(fields).eq('id', id);
    } catch (e) {
      debugPrint('Update scan error: \\$e');
    }
  }

  Future<void> _deleteScanFromDb(String id) async {
    if (_uid == null) return;
    try {
      await _sb.from('scans').delete().eq('id', id);
    } catch (e) {
      debugPrint('Delete scan error: \\$e');
    }
  }

  Future<void> _saveChatToDb(String scanId, String role, String content) async {
    if (_uid == null) return;
    try {
      await _sb.from('chat_messages').insert({
        'question_id': scanId,
        'user_id': _uid!,
        'role': role,
        'content': content,
        'is_coach_mode': false,
      });
    } catch (e) {
      debugPrint('Save scan chat error: \\$e');
    }
  }
}
"""

with open('lib/stores/scan_store.dart', 'w', encoding='utf-8') as f:
    f.write(scan_store)
print('Done - scan_store.dart')

# === EVLUMBA SERVICE ===
evlumba = """class EvlumbaService {
  static const String baseUrl = 'https://www.evlumba.com';

  static String getExploreUrl(String searchQuery) {
    return '\\$baseUrl/kesfet?q=\\${Uri.encodeComponent(searchQuery)}';
  }

  static String getCategoryUrl(String roomType) {
    final map = {
      'salon': 'Salon',
      'yatak_odasi': 'Yatak Odasi',
      'mutfak': 'Mutfak',
      'banyo': 'Banyo',
      'cocuk_odasi': 'Cocuk Odasi',
      'ofis': 'Ev Ofisi',
      'antre': 'Antre',
      'balkon': 'Balkon',
    };
    return '\\$baseUrl/kesfet?q=\\${Uri.encodeComponent(map[roomType] ?? roomType)}';
  }

  static String getDesignersUrl() => '\\$baseUrl/tasarimcilar';
  static String getGameUrl() => '\\$baseUrl/oyun';
}
"""

with open('lib/services/evlumba_service.dart', 'w', encoding='utf-8') as f:
    f.write(evlumba)
print('Done - evlumba_service.dart')
