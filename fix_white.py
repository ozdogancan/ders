f = open('lib/views/home_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# Shimmer kartlardaki griler haric, tum arka plan grilerini beyaz yap
# Shimmer'daki F1F5F9 ve F8FAFC kalsin (loading animasyonu icin gerekli)
# Diger tum F8FAFC -> FFFFFF
# Diger tum F1F5F9 -> FFFFFF

# Once shimmer kartlari koruyalim - gecici placeholder koy
c = c.replace("colors: const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)]", "colors: const [Color(0xFFSHIM1), Color(0xFFE2E8F0), Color(0xFFSHIM1)]")
c = c.replace("colors: const [Color(0xFFF8FAFC), Color(0xFFEEF2F7), Color(0xFFF8FAFC)]", "colors: const [Color(0xFFSHIM2), Color(0xFFEEF2F7), Color(0xFFSHIM2)]")

# Filtre chip arka plani: F8FAFC kalsin (secili olmayan chip)
c = c.replace("color: on ? const Color(0xFF6366F1) : const Color(0xFFF8FAFC)", "color: on ? const Color(0xFF6366F1) : const Color(0xFFCHIP1)")

# Simdi kalan tum grileri beyaz yap
c = c.replace("0xFFF8FAFC", "0xFFFFFFFF")
c = c.replace("0xFFF1F5F9", "0xFFFFFFFF")

# Placeholder'lari geri al
c = c.replace("0xFFSHIM1", "0xFFF1F5F9")
c = c.replace("0xFFSHIM2", "0xFFF8FAFC")
c = c.replace("0xFFCHIP1", "0xFFF8FAFC")

f = open('lib/views/home_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()

print('F8FAFC remaining:', c.count('0xFFF8FAFC'))
print('F1F5F9 remaining:', c.count('0xFFF1F5F9'))
print('FFFFFF count:', c.count('0xFFFFFFFF'))
print('Search tam beyaz - OK')
