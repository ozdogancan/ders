import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

// ML Kit sadece Android/iOS — web'de plugin yok. Conditional import ile
// web'de stub, mobilde gerçek implementasyon kullanılır.
import 'face_gate_stub.dart'
    if (dart.library.io) 'face_gate_mobile.dart' as impl;

/// "Bu fotoğrafta yüz var mı?" gate'i — selfie/troll fotolarını Gemini'ye
/// hit etmeden 50-100ms'de eler. On-device, ücretsiz, offline.
///
/// Kullanım:
/// ```dart
/// final verdict = await FaceGateService.check(bytes);
/// if (verdict.looksLikeSelfie) {
///   // Gemini'ye gitme, direkt "bu bir oda değil" ekranı
/// }
/// ```
class FaceGateService {
  /// MVP eşiği — face kaplama oranı > %8 ise selfie varsayımı.
  /// Küçük yüz (arkaplanda biri) mekanı bozmaz, gate geçer.
  static const double _selfieCoverageThreshold = 0.08;

  static Future<FaceVerdict> check(Uint8List bytes) async {
    if (kIsWeb) {
      // Web'de ML Kit yok; gate atlanır, Gemini yine is_room kontrolü yapar.
      return const FaceVerdict(faceCount: 0, largestCoverage: 0, skipped: true);
    }
    try {
      return await impl.detectFaces(bytes, _selfieCoverageThreshold);
    } catch (_) {
      // ML Kit herhangi bir sebeple patlarsa akışı bozma, gate'i pas geç.
      return const FaceVerdict(faceCount: 0, largestCoverage: 0, skipped: true);
    }
  }
}

class FaceVerdict {
  /// Tespit edilen yüz sayısı.
  final int faceCount;

  /// En büyük yüzün fotoğraf alanına oranı (0-1).
  final double largestCoverage;

  /// Platform desteklemediği için atlandı mı (web).
  final bool skipped;

  const FaceVerdict({
    required this.faceCount,
    required this.largestCoverage,
    this.skipped = false,
  });

  /// %8+ coverage = selfie/portre varsayımı. Mekan akışını durdur.
  bool get looksLikeSelfie =>
      !skipped && faceCount >= 1 && largestCoverage >= 0.08;
}
