import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

// ML Kit plugin'leri sadece Android/iOS — web stub.
import 'content_gate_stub.dart'
    if (dart.library.io) 'content_gate_mobile.dart' as impl;

/// "Bu fotoğraf gerçekten bir oda mı?" gate'i — Gemini'ye gitmeden
/// 80-150ms'de eler. Face detection + image labeling paralel.
///
/// Neden FaceGateService'ten ayrı:
/// - FaceGate sadece selfie yakalar.
/// - ContentGate kedi/yemek/araba/belge/ekran/giysi gibi açıkça oda olmayan
///   fotoları da yakalar.
/// - Her ret Gemini analyze'da ~$0.003 input token tasarrufu — 10k ret/ay = $30/ay.
/// - UX: kullanıcı 100 ms'de "bu bir oda değil" geri bildirimi alır, Gemini'den
///   4 sn beklemez.
///
/// Karar mantığı (conservative — emin olmadıkça reddetme):
/// - Yüz tespit + coverage ≥ %15 → SELFIE
/// - Non-room label (person/food/pet/car/document...) > 0.7 confidence VE
///   room label (furniture/couch/bed/room...) < 0.5 → NON_ROOM
/// - Her ikisi de yoksa veya ikisi birden varsa → UNKNOWN (Gemini karar versin)
///
/// Web'de ML Kit yok → kind = unknown, Gemini tek gate olur.
class ContentGateService {
  static const double _nonRoomConfidence = 0.7;
  static const double _roomIndicatorConfidence = 0.5;

  static Future<ContentVerdict> check(Uint8List bytes) async {
    if (kIsWeb) {
      return const ContentVerdict(
        kind: ContentKind.unknown,
        skipped: true,
        topLabels: [],
      );
    }
    try {
      return await impl.gateContent(
        bytes,
        nonRoomThreshold: _nonRoomConfidence,
        roomIndicatorThreshold: _roomIndicatorConfidence,
      );
    } catch (_) {
      // Plugin patlarsa akışı bozma.
      return const ContentVerdict(
        kind: ContentKind.unknown,
        skipped: true,
        topLabels: [],
      );
    }
  }
}

/// Karar tipi — mekan_flow_screen bunu tek switch ile map'ler.
enum ContentKind {
  /// İnsan yüzü baskın — selfie/portre.
  selfie,

  /// Kedi, yemek, araba, belge, ekran gibi açıkça oda olmayan içerik.
  nonRoom,

  /// İç mekan göstergesi (mobilya, oda, duvar) var — devam.
  room,

  /// Belirsiz — Gemini karar versin.
  unknown,
}

class ContentVerdict {
  final ContentKind kind;

  /// Platform desteklemediği için atlandı mı (web) veya plugin hatası mı.
  final bool skipped;

  /// Debug/log için en yüksek confidence'lı 3 label (plugin'den).
  final List<String> topLabels;

  /// Non-room ise hangi kategoride (person/food/pet/vehicle/document/screen/clothing).
  /// UX mesajını kişiselleştirmek için.
  final String? nonRoomCategory;

  const ContentVerdict({
    required this.kind,
    required this.topLabels,
    this.skipped = false,
    this.nonRoomCategory,
  });

  bool get shouldBlock => kind == ContentKind.selfie || kind == ContentKind.nonRoom;
}
