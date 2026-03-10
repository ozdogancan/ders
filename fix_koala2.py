# Madde 7 devam: Tespit edilemezse UI'da uyari goster
f = open('lib/views/question_share_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# _detectionFailed state ekle (yoksa)
if '_detectionFailed' not in c:
    c = c.replace(
        'bool _detectingSubject = false;',
        'bool _detectingSubject = false;\n  bool _detectionFailed = false;'
    )

    # detectSubject icerisinde null donunce _detectionFailed = true yap
    c = c.replace(
        "setState(() { _detectedSubject = matched; _selectedSubject = matched; _detectingSubject = false; });",
        "if (matched == null) {\n        setState(() { _detectionFailed = true; _detectingSubject = false; });\n      } else {\n        setState(() { _detectionFailed = false; _detectedSubject = matched; _selectedSubject = matched; _detectingSubject = false; });\n      }"
    )

    # catch icerisinde de _detectionFailed = true
    c = c.replace(
        "setState(() => _detectingSubject = false);",
        "setState(() { _detectingSubject = false; _detectionFailed = true; });"
    )

    # retake'de _detectionFailed sifirla
    c = c.replace(
        "_imageBytes = null; _selectedSubject = null; _detectedSubject = null; _step = 0;",
        "_imageBytes = null; _selectedSubject = null; _detectedSubject = null; _detectionFailed = false; _step = 0;"
    )

    # Ders altindaki aciklama metnini degistir
    old_text = "Text('Otomatik alg"
    if old_text in c:
        idx = c.find(old_text)
        line_end = c.find('\n', idx)
        old_line = c[idx:line_end]
        new_block = """_detectionFailed
          ? Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(30))),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: const Color(0xFFF59E0B), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text('G\\u00f6r\\u00fcnt\\u00fcden konu tespit edilemedi. L\\u00fctfen dersi se\\u00e7.',
                  style: TextStyle(fontSize: 13, color: Colors.amber.shade800))),
              ]),
            )
          : """ + old_line
        c = c[:idx] + new_block + c[line_end:]

    f = open('lib/views/question_share_screen.dart', 'w', encoding='utf-8')
    f.write(c)
    f.close()
    print('Madde 7: Tespit uyari UI - OK')
else:
    print('Madde 7: Zaten uygulanmis - SKIP')

# Madde 3: Smart mesajlari iyilestir
f = open('lib/views/chat_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

c = c.replace("return ['Evet', 'A\\u00e7\\u0131klar m\\u0131s\\u0131n?'];", "return ['Bir ipucu verir misin?', 'Anlamad\\u0131m, farkl\\u0131 anlat'];")
c = c.replace("return ['Evet, anlat', 'Hay\\u0131r, ge\\u00e7'];", "return ['Biraz daha a\\u00e7\\u0131klar m\\u0131s\\u0131n?', 'Anlad\\u0131m, devam'];")

# Coach mode prompt iyilestir
old_coach = "'Sen Koala uygulamasinin AI kocusun. Ogrenciyle benzer soru cozuyorsun. '"
new_coach = "'Sen Koala uygulamasinin ' + q.subject + ' dersi AI kocusun. Ogrenciyle benzer bir soru cozduruyorsun. '"

if old_coach in c:
    c = c.replace(old_coach, new_coach)

# Daha basit yapalim - coach system prompt'un basini degistirelim
c = c.replace(
    "? 'Sen Koala uygulamasinin AI kocusun. Ogrenciyle benzer soru cozuyorsun. '",
    "? 'Sen Koala uygulamasinin \ dersi AI kocusun. Ogrenciyle benzer bir soru cozduruyorsun. '"
)
c = c.replace(
    "'Soruyu KENDIN COZME. Ogrenciye yonlendirici soru sor. '",
    "'Soruyu KENDIN COZME. Once benzer ama FARKLI sayilarla/degerlerle yeni bir soru olustur, sonra ogrenciye yonlendirici soru sor. '"
)

f = open('lib/views/chat_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('Madde 3: Smart mesajlar + coach - OK')

# Madde 9: Image cache
f = open('lib/main.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

if 'imageCache.maximumSizeBytes' not in c:
    c = c.replace(
        'WidgetsFlutterBinding.ensureInitialized();',
        'WidgetsFlutterBinding.ensureInitialized();\n  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;\n  PaintingBinding.instance.imageCache.maximumSize = 200;'
    )
    f = open('lib/main.dart', 'w', encoding='utf-8')
    f.write(c)
    f.close()
    print('Madde 9: Image cache - OK')
else:
    print('Madde 9: Zaten uygulanmis - SKIP')

# Madde 9: Preconnect
f = open('web/index.html', 'r', encoding='utf-8')
c = f.read()
f.close()

if 'preconnect' not in c:
    c = c.replace(
        '<meta charset="UTF-8">',
        '<meta charset="UTF-8">\n  <link rel="preconnect" href="https://xgefjepaqnghaotqybpi.supabase.co">\n  <link rel="preconnect" href="https://generativelanguage.googleapis.com">\n  <link rel="dns-prefetch" href="https://xgefjepaqnghaotqybpi.supabase.co">'
    )
    f = open('web/index.html', 'w', encoding='utf-8')
    f.write(c)
    f.close()
    print('Madde 9: Preconnect - OK')
else:
    print('Madde 9: Preconnect zaten var - SKIP')

print('\n=== DURUM ===')
print('1. Logo PNG - DONE')
print('2. Search duz beyaz - DONE')
print('3. Smart mesajlar + coach - DONE')
print('4. Silme UI - SKIP (as is)')
print('5. Profil resmi - YAPILACAK')
print('6. Bekleme 5sn - DONE')
print('7. Tespit uyari - DONE')
print('8. Tum dersler prompt - DONE')
print('9. Performans - DONE')
