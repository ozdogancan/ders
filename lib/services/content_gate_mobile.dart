import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'content_gate_service.dart';

/// Non-room label kategorileri. ML Kit default model ~400 etiket döner;
/// burada "açıkça oda değil" kategoriler var. Her biri bir mesaj tonu.
///
/// NOT: ML Kit label'ları hep İngilizce, büyük harfle başlar ("Cat", "Food").
/// Tüm karşılaştırmalar lowercase.
const Map<String, List<String>> _nonRoomLabels = {
  'person': ['person', 'face', 'selfie', 'portrait', 'human'],
  'food': ['food', 'dish', 'dessert', 'breakfast', 'lunch', 'dinner',
           'fast food', 'junk food', 'meal', 'snack', 'fruit', 'vegetable',
           'baked goods', 'bread', 'pizza', 'burger', 'cake'],
  'pet': ['cat', 'dog', 'pet', 'animal', 'bird', 'fish', 'hamster', 'rabbit'],
  'vehicle': ['car', 'vehicle', 'motorcycle', 'bicycle', 'truck', 'bus',
              'boat', 'airplane', 'wheel'],
  'document': ['document', 'paper', 'text', 'book', 'newspaper', 'receipt',
               'handwriting'],
  'screen': ['computer monitor', 'laptop', 'phone', 'television',
             'mobile phone', 'display device', 'electronic device'],
  'clothing': ['clothing', 'dress', 'shirt', 'pants', 'shoes', 'fashion',
               'jacket', 'jeans', 'sneakers'],
  'outdoor': ['sky', 'tree', 'mountain', 'beach', 'ocean', 'forest',
              'landscape', 'nature', 'garden'],
};

/// Oda-göstergesi label'lar — bunlardan biri yüksek confidence'la varsa
/// non-room label'larına rağmen "şüpheli ama belki oda" → unknown → Gemini.
const List<String> _roomIndicatorLabels = [
  'room', 'living room', 'bedroom', 'kitchen', 'bathroom', 'dining room',
  'interior design', 'furniture', 'couch', 'sofa', 'bed', 'chair', 'table',
  'shelf', 'cabinet', 'wall', 'ceiling', 'floor', 'window', 'door', 'curtain',
  'lamp', 'lighting', 'rug', 'carpet', 'bathtub', 'sink', 'toilet',
  'refrigerator', 'oven', 'desk', 'bookcase', 'wardrobe',
];

/// Mobil (Android/iOS) ContentGate — face detection + image labeling paralel.
Future<ContentVerdict> gateContent(
  Uint8List bytes, {
  required double nonRoomThreshold,
  required double roomIndicatorThreshold,
}) async {
  final dir = await getTemporaryDirectory();
  final path = p.join(dir.path,
      'content_gate_${DateTime.now().millisecondsSinceEpoch}.jpg');
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);

  final faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: false,
      enableClassification: false,
      enableContours: false,
      enableTracking: false,
      minFaceSize: 0.15,
    ),
  );
  final labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.4),
  );

  try {
    final inputImage = InputImage.fromFilePath(file.path);

    // Paralel: face + label. İkisi birden tamamlansın.
    final results = await Future.wait([
      faceDetector.processImage(inputImage),
      labeler.processImage(inputImage),
    ]);
    final faces = results[0] as List<Face>;
    final labels = results[1] as List<ImageLabel>;

    // Debug için en iyi 3 label.
    final topLabels = labels.take(3).map((l) => '${l.label}:${l.confidence.toStringAsFixed(2)}').toList();

    // 1) Selfie check — face var ve minFaceSize 0.15 geçmiş.
    if (faces.isNotEmpty) {
      return ContentVerdict(
        kind: ContentKind.selfie,
        topLabels: topLabels,
        nonRoomCategory: 'person',
      );
    }

    // 2) Room indicator var mı?
    double maxRoomIndicator = 0;
    for (final l in labels) {
      final name = l.label.toLowerCase();
      if (_roomIndicatorLabels.contains(name) && l.confidence > maxRoomIndicator) {
        maxRoomIndicator = l.confidence;
      }
    }

    // 3) Non-room kategori var mı?
    String? nonRoomCategory;
    double maxNonRoom = 0;
    for (final l in labels) {
      final name = l.label.toLowerCase();
      for (final entry in _nonRoomLabels.entries) {
        if (entry.value.contains(name) && l.confidence > maxNonRoom) {
          maxNonRoom = l.confidence;
          nonRoomCategory = entry.key;
        }
      }
    }

    // Karar matrisi:
    // - Güçlü non-room sinyal VE oda göstergesi yok → reddet.
    // - Oda göstergesi var → geç (room). Non-room sinyali zayıfsa bile.
    // - Hiçbiri yok → unknown (Gemini karar verir).
    if (maxNonRoom >= nonRoomThreshold && maxRoomIndicator < roomIndicatorThreshold) {
      return ContentVerdict(
        kind: ContentKind.nonRoom,
        topLabels: topLabels,
        nonRoomCategory: nonRoomCategory,
      );
    }
    if (maxRoomIndicator >= roomIndicatorThreshold) {
      return ContentVerdict(
        kind: ContentKind.room,
        topLabels: topLabels,
      );
    }
    return ContentVerdict(
      kind: ContentKind.unknown,
      topLabels: topLabels,
    );
  } finally {
    await faceDetector.close();
    await labeler.close();
    try {
      await file.delete();
    } catch (_) {}
  }
}
