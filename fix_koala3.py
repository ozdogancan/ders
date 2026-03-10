f = open('lib/widgets/koala_logo.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# KoalaHero'dan "Koala" ve "Ogrenmenin en tatli yolu" textlerini kaldir
# Sadece logo resmi kalsin
new_content = '''import 'package:flutter/material.dart';

class KoalaLogo extends StatelessWidget {
  const KoalaLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/koala_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.school, size: size, color: Colors.grey),
    );
  }
}

class KoalaHero extends StatelessWidget {
  const KoalaHero({super.key, this.size = 120});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/koala_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.school, size: size, color: Colors.grey),
    );
  }
}
'''

f = open('lib/widgets/koala_logo.dart', 'w', encoding='utf-8')
f.write(new_content)
f.close()
print('1. KoalaHero text kaldirildi - OK')

# ── Search bar: arka plan FULL BEYAZ, icerideki renk yok
f = open('lib/views/home_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# Mobile search arka plan rengi: F8FAFC (gri) -> FFFFFF (beyaz)
c = c.replace("backgroundColor: wide ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC)", "backgroundColor: Colors.white")

# Search container icindeki fill rengi de beyaz olmali - border sadece E2E8F0
# Zaten degistirdik ama arka plan hala gri olabilir
# Scaffold arka planini beyaz yap
c = c.replace(
    "return Scaffold(backgroundColor: wide ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),",
    "return Scaffold(backgroundColor: Colors.white,"
)

# Filtre seceneklerine "Cevap Bekleniyor" ekle
c = c.replace(
    "_chip('\\u00c7\\u00f6z\\u00fcl\\u00fcyor', _fStatus == 'solving', () { ss(() {}); setState(() => _fStatus = 'solving'); }),",
    "_chip('\\u00c7\\u00f6z\\u00fcl\\u00fcyor', _fStatus == 'solving', () { ss(() {}); setState(() => _fStatus = 'solving'); }),\n              _chip('Cevap Bekleniyor', _fStatus == 'waiting', () { ss(() {}); setState(() => _fStatus = 'waiting'); }),"
)

# waiting filtresini _filtered()'a ekle
c = c.replace(
    "if (_fStatus == 'solving') list = list.where((i) => i.status == QStatus.solving).toList();",
    "if (_fStatus == 'solving') list = list.where((i) => i.status == QStatus.solving).toList();\n    else if (_fStatus == 'waiting') list = list.where((i) => i.status == QStatus.waitingAnswer).toList();"
)

# Profil resmi: sag ustteki person ikonu yerine _photoUrl varsa NetworkImage goster
# Once profile_screen'den photo_url'i alip home'da kullanmamiz lazim
# En basit yol: FirebaseAuth currentUser.photoURL kullanmak
if "import 'package:firebase_auth/firebase_auth.dart';" not in c:
    c = c.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:firebase_auth/firebase_auth.dart';"
    )

# Profil avatar widget'ini degistir
c = c.replace(
    '''Container(
                width: 38, height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
              )''',
    '''Builder(builder: (_) {
                final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
                return Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: photoUrl == null ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]) : null,
                    border: photoUrl != null ? Border.all(color: const Color(0xFF6366F1).withAlpha(40), width: 2) : null,
                  ),
                  child: photoUrl != null
                    ? ClipOval(child: Image.network(photoUrl, width: 38, height: 38, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 18)))
                    : const Icon(Icons.person_rounded, color: Colors.white, size: 18),
                );
              })'''
)

f = open('lib/views/home_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('2. Search full beyaz + filtre + profil resmi - OK')

# ── Chat ekraninda AI soru sordugunda status "waitingAnswer" olmali
# question_store.dart'ta QStatus'a waitingAnswer ekle (varsa)
f = open('lib/stores/question_store.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

if 'waitingAnswer' not in c:
    c = c.replace(
        'enum QStatus { solving, solved, error }',
        'enum QStatus { solving, solved, error, waitingAnswer }'
    )
print('3. QStatus waitingAnswer kontrol - OK')

# Chat'te AI soru sordugunda (? ile bitiyorsa) status'u waitingAnswer yap
# Bu biraz karmasik - chat_screen'de _sendMsg sonrasi kontrol eklemek lazim
# Simdilik basit tutalim: AI mesaji ? ile bitiyorsa status degistir

f = open('lib/stores/question_store.dart', 'w', encoding='utf-8')
f.write(c)
f.close()

# ── Chat screen: coach modunda veya AI soru sordugunda
# _prev fonksiyonunda waitingAnswer icin mesaj ekle
f = open('lib/views/home_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

c = c.replace(
    "if (q.status == QStatus.error) return 'Bir hata olustu, kredin iade edildi.';",
    "if (q.status == QStatus.error) return 'Bir hata olustu, kredin iade edildi.';\n    if (q.status == QStatus.waitingAnswer) return 'Koala sana bir soru sordu, cevabini bekliyor...';"
)

# waitingAnswer icin badge
c = c.replace(
    "if (solving) _B(l: '\\u00c7\\u00f6z\\u00fcl\\u00fcyor', c: Colors.amber.shade700, spin: true)",
    "if (q.status == QStatus.waitingAnswer) const _B(l: 'Cevap Bekliyor', c: Color(0xFF6366F1), ic: Icons.question_answer_rounded)\n                  else if (solving) _B(l: '\\u00c7\\u00f6z\\u00fcl\\u00fcyor', c: Colors.amber.shade700, spin: true)"
)

f = open('lib/views/home_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('4. WaitingAnswer badge + preview - OK')

# ── Chat screen'de AI soru sordugunda status guncelle
f = open('lib/views/chat_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# _sendMsg icinde AI cevabi geldikten sonra soru mu kontrol et
old_add_chat = "QuestionStore.instance.addChat(q.id, ChatMsg(role: 'ai', text: reply));"
new_add_chat = """QuestionStore.instance.addChat(q.id, ChatMsg(role: 'ai', text: reply));
      // AI soru sorduysa status'u waitingAnswer yap
      if (reply.trim().endsWith('?') && _coachMode) {
        QuestionStore.instance.setWaitingAnswer(q.id);
      }"""

c = c.replace(old_add_chat, new_add_chat, 1)

f = open('lib/views/chat_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('5. Chat AI soru -> waitingAnswer - OK')

# ── question_store.dart'a setWaitingAnswer metodu ekle
f = open('lib/stores/question_store.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

if 'setWaitingAnswer' not in c:
    # setError metodunun hemen altina ekle
    c = c.replace(
        'void setError(String id) {',
        '''void setWaitingAnswer(String id) {
    final idx = _questions.indexWhere((q) => q.id == id);
    if (idx < 0) return;
    _questions[idx] = _questions[idx].copyWith(status: QStatus.waitingAnswer);
    notifyListeners();
  }

  void setError(String id) {'''
    )

f = open('lib/stores/question_store.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('6. setWaitingAnswer metodu - OK')

print('\n=== TAMAMLANDI ===')
print('- KoalaHero text kaldirildi')
print('- Scaffold arka plan beyaz')
print('- Filtre: Cevap Bekleniyor eklendi')
print('- Profil resmi sag ustte gozukuyor')
print('- AI soru sordugunda waitingAnswer status')
