import 'dart:typed_data';
import 'face_gate_service.dart';

// Web stub — ML Kit native plugin web'de çalışmaz.
Future<FaceVerdict> detectFaces(Uint8List _, double _) async {
  return const FaceVerdict(faceCount: 0, largestCoverage: 0, skipped: true);
}
