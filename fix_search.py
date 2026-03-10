f = open('lib/views/home_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# Search container'in icindeki beyaz olmayan renkleri temizle
# Container zaten beyaz ama TextField'in filled ozelligi olabilir
# Ayrica focusedBorder'i da transparent yapalim

# Search input'taki tum decoration'lari kontrol et
# Container border: E2E8F0 (bu OK, ince gri cizgi)
# Ama icerideki TextField'e bakmamiz lazim

# Sorun: search container'in arka plani beyaz ama
# borderRadius icinde baska bir renk gorunuyor olabilir
# Butun search-related Color(0xFFF8FAFC) ve Color(0xFFF1F5F9) referanslarini beyaz yapalim

c = c.replace("color: const Color(0xFFF8FAFC),\n                  borderRadius: BorderRadius.circular(12),", "color: Colors.white,\n                  borderRadius: BorderRadius.circular(12),")
c = c.replace("color: const Color(0xFFF8FAFC),\n                  borderRadius: BorderRadius.circular(14),", "color: Colors.white,\n                  borderRadius: BorderRadius.circular(14),")

# Web search icindeki gri renk
c = c.replace("color: const Color(0xFFF8FAFC),\n                borderRadius: BorderRadius.circular(12),\n                border: Border.all(color: const Color(0xFFE8ECF4))", "color: Colors.white,\n                borderRadius: BorderRadius.circular(12),\n                border: Border.all(color: const Color(0xFFE2E8F0))")

f = open('lib/views/home_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('Search icerik full beyaz - OK')
