f = open('lib/stores/question_store.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

old = "var jsonStr = match.group(0)!;"
if old in c:
    print('jsonStr zaten var, sadece fallback ekle')
    # replaceAllMapped var ama directDecode yok - kontrol et
    idx = c.find('var jsonStr')
    snippet = c[idx:idx+500]
    print(snippet[:200])
else:
    # Eski basit parse - degistir
    old_simple = "final decoded = jsonDecode(match.group(0)!) as Map<String, dynamic>;"
    if old_simple in c:
        new_parse = """var jsonStr = match.group(0)!;
      jsonStr = jsonStr.replaceAll(RegExp(r'[\\x00-\\x09\\x0b\\x0c\\x0e-\\x1f]'), ' ');
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        jsonStr = jsonStr.replaceAllMapped(
          RegExp(r'(?<!\\\\)\\\\(?!\\\\|"|/|n|t|r|b|f|u[0-9a-fA-F])'),
          (m) => '\\\\\\\\',
        );
        decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      }"""
        c = c.replace(old_simple, new_parse)
        print('LaTeX escape fix eklendi')
    else:
        print('HATA: parse kodu bulunamadi')

f = open('lib/stores/question_store.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('DONE')
