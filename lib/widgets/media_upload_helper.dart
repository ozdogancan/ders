import 'dart:typed_data';

/// Medya upload yardımcısı — magic byte'tan MIME detect + uzantı eşleme.
///
/// Supabase Storage upload'unda `FileOptions.contentType` ile dosya
/// uzantısının tutarlı olması gerekiyor; aksi halde bazı view katmanlarında
/// (ör. resize proxy, browser download) "application/octet-stream" olarak
/// servis ediliyor ve <img> tag'inde broken image çıkıyordu.
///
/// Not: `koala_ai_service.dart:_detectMimeType` mantığı birebir burada.
/// Tek doğruluk kaynağı (SSOT) olarak helper'ı kullanıyoruz.
class MediaUploadHelper {
  MediaUploadHelper._();

  /// Byte dizisinin ilk imzasına bakarak MIME type döner.
  /// Destek: JPEG, PNG, WEBP, GIF, HEIC. Tanınmayan içerik 'image/jpeg'e düşer.
  static String detectMime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  /// MIME → dosya uzantısı (nokta olmadan: 'jpg', 'png', 'webp'...).
  /// Bilinmeyen tipler 'jpg' olarak döner.
  static String extensionFor(String mime) {
    switch (mime) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/heic':
        return 'heic';
      case 'image/jpeg':
      default:
        return 'jpg';
    }
  }
}
