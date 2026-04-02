import re

path = 'lib/views/home_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

replacements = {
    'odamÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±': 'odamı',
    'renk ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¶nerisi': 'renk önerisi',
    'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼rÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼n keÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸fet': 'ürün keşfet',
    'aydÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±nlat': 'aydınlat',
    'kontrolcÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼leri': 'kontrolcüleri',
    'ÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â°yi': 'İyi',
    'GÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼naydÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±n': 'Günaydın',
    'akÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸amlar': 'akşamlar',
    'ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬': '──',
    'FotoÃƒÆ’Ã¢â‚¬ÂžÃƒâ€¦Ã‚Â¸raf': 'Fotoğraf',
    'alÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±ndÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±': 'alındı',
    'ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢': '→',
    'baÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸lat': 'başlat',
    'TÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼mÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼': 'Tümü',
    'KeÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸fet': 'Keşfet',
    'TarzÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±': 'Tarzı',
    'DoÃƒÆ’Ã¢â‚¬ÂžÃƒâ€¦Ã‚Â¸al': 'Doğal',
    'ahÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸ap': 'ahşap',
    'ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¡izgiler': 'Çizgiler',
    'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¶ÃƒÆ’Ã¢â‚¬ÂžÃƒâ€¦Ã‚Â¸eler': 'öğeler',
    'DokunuÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸lar': 'Dokunuşlar',
    'CanlÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±': 'Canlı',
    'HÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±zlÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±': 'Hızlı',
    'EriÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸im': 'Erişim',
    'ÃƒÆ’Ã†â€™Ãƒâ€¦Ã¢â‚¬Å“rÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼n': 'Ürün',
    'BÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼tÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â§ene': 'Bütçene',
    'EÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸leÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸': 'Eşleş',
    'ÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â°ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â§': 'İç',
    'OluÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸tur': 'Oluştur',
    'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¶nerisi': 'önerisi',
    'MekanÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±': 'Mekanı',
    'OdanÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±': 'Odanı',
    'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â§ek': 'çek',
    'dÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¶nÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸tÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼r': 'dönüştür',
    'BaÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€¦Ã‚Â¸la': 'Başla',
    'ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚Â ': '',
    'ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢Ãƒâ€šÃ‚Â ': '',
    'dÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¶nen': 'dönen',
    'kullanÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±cÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±ysa': 'kullanıcıysa',
    'gÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¶rmeli': 'görmeli',
    'ÃƒÆ’Ã¢â‚¬ÂžÃƒâ€šÃ‚Â±': 'ı',
    'ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¼': 'ü',
}

for bad, good in replacements.items():
    text = text.replace(bad, good)

# Fix syntax errors exactly here too

# 1. The extra dispose
text = text.replace('''  @override
  void dispose() {
    _ctrl.dispose();
      _inputCtrl.dispose();
    super.dispose();
  }''', '''  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }''')

# 2. The extra closing brackets at Expanded
bad_brackets = '''                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1D2A),
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector('''
good_brackets = '''                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1D2A),
                    ),
                  ),
                ),
            GestureDetector('''
text = text.replace(bad_brackets, good_brackets)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print('Mojibake fixed and syntax errors resolved')
