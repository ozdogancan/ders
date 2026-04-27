import 'dart:typed_data';
import 'content_gate_service.dart';

/// Web stub — ML Kit plugin'leri web'de yok, her zaman "unknown" döner.
Future<ContentVerdict> gateContent(
  Uint8List _, {
  required double nonRoomThreshold,
  required double roomIndicatorThreshold,
}) async {
  return const ContentVerdict(
    kind: ContentKind.unknown,
    skipped: true,
    topLabels: [],
  );
}
