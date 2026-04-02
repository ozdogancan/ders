p = 'lib/models/scan_analysis.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace(
    "  int get colorValue {\n    final clean = hex.replaceAll('#', '');\n    return int.tryParse('FF', radix: 16) ?? 0xFF000000;\n  }",
    "  int get colorValue {\n    final h = hex.replaceAll('#', '');\n    return int.tryParse('FF\$h', radix: 16) ?? 0xFF000000;\n  }"
)
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done')
