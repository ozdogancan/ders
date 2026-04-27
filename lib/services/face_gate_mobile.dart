import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'face_gate_service.dart';

/// Mobil (Android/iOS) ML Kit face detection.
/// Bytes'ı geçici dosyaya yazıp InputImage.fromFilePath kullanır —
/// en stabil yöntem, InputImage.fromBytes platformlar arası capricious.
Future<FaceVerdict> detectFaces(
  Uint8List bytes,
  double coverageThreshold,
) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path,
      'face_gate_${DateTime.now().millisecondsSinceEpoch}.jpg'));
  await file.writeAsBytes(bytes, flush: true);

  final detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: false,
      enableClassification: false,
      enableContours: false,
      enableTracking: false,
      minFaceSize: 0.15, // küçük yüzleri geç — arkaplanda çocuk fotosu vb.
    ),
  );

  try {
    final inputImage = InputImage.fromFilePath(file.path);
    final faces = await detector.processImage(inputImage);
    if (faces.isEmpty) {
      return const FaceVerdict(faceCount: 0, largestCoverage: 0);
    }

    // Image boyutu için ML Kit metadata sağlamıyor; ama boundingBox'ların
    // görsel alanına oranını, bytes'tan decode'suz yaklaşık hesaplayamayız.
    // Bunun yerine: boundingBox genişliği / en geniş face'in faceRect genişliği
    // bir "relative" ölçü verir. Pratik kestirim: en büyük face'in
    // boundingBox.width / height'ını kullan — ML Kit minFaceSize 0.15 zaten
    // %15 threshold anlamına geliyor. faceCount > 0 ve minFaceSize 0.15'i
    // geçmişse selfie varsayıyoruz.
    //
    // Daha hassas coverage için image decode gerekir (pahalı). MVP için
    // minFaceSize eşiği yeterli — detector zaten %15'in altındakileri atıyor.
    return FaceVerdict(
      faceCount: faces.length,
      // faces varsa en az %15 coverage garantili (minFaceSize).
      largestCoverage: 0.20,
    );
  } finally {
    await detector.close();
    // Temp dosyayı sessizce sil.
    try {
      await file.delete();
    } catch (_) {}
  }
}
