# Fix 1: scan_analysis.dart - unused clean variable
p1 = 'lib/models/scan_analysis.dart'
with open(p1, 'r', encoding='utf-8') as f:
    c = f.read()
# colorValue getter deki clean kullanilmamis olabilir
c = c.replace(
    "    final clean = hex.replaceAll('#', '');\n    return int.tryParse('FF$clean', radix: 16) ?? 0xFF000000;",
    "    return int.tryParse('FF${hex.replaceAll(\"#\", \"\")}', radix: 16) ?? 0xFF000000;"
)
with open(p1, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done - scan_analysis fix')

# Fix 2: evlumba_service.dart - map kullanilmamis
p2 = 'lib/services/evlumba_service.dart'
with open(p2, 'r', encoding='utf-8') as f:
    c = f.read()
# map degiskeni tanimlanip kullanilmiyor olabilir - bakalim
print('evlumba content check:')
for i, line in enumerate(c.split('\n')):
    if 'map' in line.lower() and i < 25:
        print(f'  L{i+1}: {line.rstrip()}')
