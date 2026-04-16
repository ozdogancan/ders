/// Stub for non-web platforms — no-op implementations.
import 'dart:typed_data';

void registerWebDrop({
  required void Function(Uint8List bytes) onDrop,
  required void Function(bool hovering) onHover,
}) {}

void unregisterWebDrop() {}
