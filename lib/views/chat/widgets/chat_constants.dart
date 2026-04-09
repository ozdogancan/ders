import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';

const accent = KoalaColors.accentDeep;
const accentLight = KoalaColors.accentSoft;
const ink = KoalaColors.ink;
const R = 18.0;

Color hex(String h) {
  final clean = h.replaceAll('#', '');
  return Color(
    int.tryParse('FF$clean', radix: 16) ?? KoalaColors.accentDeep.toARGB32(),
  );
}
