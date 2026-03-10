import re

# Madde 2: Search bar shadow kaldir
f = open('lib/views/home_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

c = c.replace('height: 52,', 'height: 48,', 1)
c = c.replace('borderRadius: BorderRadius.circular(16),\n                  border: Border.all(color: const Color(0xFFE8ECF4)),\n                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))])', 'borderRadius: BorderRadius.circular(14),\n                  border: Border.all(color: const Color(0xFFE2E8F0)))', 1)
c = c.replace('width: 52, height: 52,', 'width: 48, height: 48,', 1)
c = c.replace('borderRadius: BorderRadius.circular(16),\n                    border: Border.all(color: hasF ? const Color(0xFF6366F1) : const Color(0xFFE8ECF4)),\n                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))])', 'borderRadius: BorderRadius.circular(14),\n                    border: Border.all(color: hasF ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)))', 1)

f = open('lib/views/home_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('Madde 2: Search duz beyaz - OK')

# Madde 6: Bekleme 10sn -> 5sn
f = open('lib/views/question_share_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

c = c.replace('elapsed < 10000', 'elapsed < 5000')
c = c.replace('milliseconds: 10000 - elapsed', 'milliseconds: 5000 - elapsed')

# Madde 7: Tespit edilemezse null
c = c.replace("else { matched = 'Matematik'; }", "else { matched = null; }")

f = open('lib/views/question_share_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('Madde 6: Bekleme 5sn - OK')
print('Madde 7: Tespit fallback null - OK')
