
import re

path = 'lib/views/home_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# I will find the common mojibake patterns based on their byte representation or just use raw strings
# The strings are already in the file. I can fetch them via a simple regex looking for 'ÃƒÆ' and mapping them to correct chars.
# Let's map the EXACT byte strings.
mangled = {
    'odamÃƒÆÃâÂžÃƒâ€šÃÂ': 'odamı',
    'renk ÃƒÆÃâ€Ãƒâ€šÃÂnerisi': 'renk önerisi',
    'ÃƒÆÃâ€Ãƒâ€šÃÂrÃƒÆÃâ€Ãƒâ€šÃÂn keÃƒÆÃâÂÃƒâ€ÃÂfet': 'ürün keşfet',
    'aydÃƒÆÃâÂžÃƒâ€šÃÂnlat': 'aydınlat',
    'kontrolcÃƒÆÃâ€Ãƒâ€šÃÂleri': 'kontrolcüleri',
    'ÃƒÆÃâÂžÃƒâ€šÃÂyi': 'İyi',
    'GÃƒÆÃâ€Ãƒâ€šÃÂnaydÃƒÆÃâÂžÃƒâ€šÃÂn': 'Günaydın',
    'akÃƒÆÃâÂÃƒâ€ÃÂamlar': 'akşamlar',
    'ÃƒÆÃÂÃƒÂÃâ€šÂÃÂ ÃƒÂÃâÅÃÂÃƒÆÃÂÃƒÂÃâ€šÂÃÂ ÃƒÂÃâÅÃÂ': '',
    'FotoÃƒÆÃâÂžÃƒâ€ÃÂraf': 'Fotoğraf',
    'alÃƒÆÃâÂžÃƒâ€šÃÂndÃƒÆÃâÂžÃƒâ€šÃÂ': 'alındı',
    'ÃƒÆÃÂÃƒÂÃâ€šÂÃÂÃƒÂÃâ€šÂÃâ€žÂ': '',
    'baÃƒÆÃâÂÃƒâ€ÃÂlat': 'başlat',
    'TÃƒÆÃâ€Ãƒâ€šÃÂmÃƒÆÃâ€Ãƒâ€šÃÂ': 'Tümü',
    'KeÃƒÆÃâÂÃƒâ€ÃÂfet': 'Keşfet',
    'TarzÃƒÆÃâÂžÃƒâ€šÃÂ': 'Tarzı',
    'DoÃƒÆÃâÂžÃƒâ€ÃÂal': 'Doğal',
    'ahÃƒÆÃâÂÃƒâ€ÃÂap': 'ahşap',
    'ÃƒÆÃâ€ÃƒÂÃâ€šÂÃÂizgiler': 'Çizgiler',
    'ÃƒÆÃâ€Ãƒâ€šÃÂÃƒÆÃâÂžÃƒâ€ÃÂeler': 'öğeler',
    'DokunuÃƒÆÃâÂÃƒâ€ÃÂlar': 'Dokunuşlar',
    'CanlÃƒÆÃâÂžÃƒâ€šÃÂ': 'Canlı',
    'HÃƒÆÃâÂžÃƒâ€šÃÂzlÃƒÆÃâÂžÃƒâ€šÃÂ': 'Hızlı',
    'EriÃƒÆÃâÂÃƒâ€ÃÂim': 'Erişim',
    'ÃƒÆÃâ€Ãƒâ€ÃâÅrÃƒÆÃâ€Ãƒâ€šÃÂn': 'Ürün',
    'BÃƒÆÃâ€Ãƒâ€šÃÂtÃƒÆÃâ€Ãƒâ€šÃÂene': 'Bütçene',
    'EÃƒÆÃâÂÃƒâ€ÃÂleÃƒÆÃâÂÃƒâ€ÃÂ': 'Eşleş',
    'ÃƒÆÃâÂžÃƒâ€šÃÂÃƒÆÃâ€Ãƒâ€šÃÂ': 'İç',
    'OluÃƒÆÃâÂÃƒâ€ÃÂtur': 'Oluştur',
    'ÃƒÆÃâ€Ãƒâ€šÃÂnerisi': 'önerisi',
    'MekanÃƒÆÃâÂžÃƒâ€šÃÂ': 'Mekanı',
    'OdanÃƒÆÃâÂžÃƒâ€šÃÂ': 'Odanı',
    'ÃƒÆÃâ€Ãƒâ€šÃÂek': 'çek',
    'dÃƒÆÃâ€Ãƒâ€šÃÂnÃƒÆÃâ€Ãƒâ€šÃÂÃƒÆÃâÂÃƒâ€ÃÂtÃƒÆÃâ€Ãƒâ€šÃÂr': 'dönüştür',
    'BaÃƒÆÃâÂÃƒâ€ÃÂla': 'Başla',
    'ÃƒÆÃÂÃƒÂÃâ€šÂÃÂÃƒâ€šÃÂ': '',
    'ÃƒÆÃÂÃƒÂÃâ€šÂÃÂÃƒâ€šÃÂ ': '',
    'dÃƒÆÃâ€Ãƒâ€šÃÂnen': 'dönen',
    'kullanÃƒÆÃâÂžÃƒâ€šÃÂcÃƒÆÃâÂžÃƒâ€šÃÂysa': 'kullanıcıysa',
    'gÃƒÆÃâ€Ãƒâ€šÃÂrmeli': 'görmeli',
    'ÃƒÆÃâÂžÃƒâ€šÃÂ': 'ı',
    'ÃƒÆÃâ€Ãƒâ€šÃÂ': 'ü',
}

# The dictionary keys are UTF-8 encodings of latin-1 encodings of... something. It's safer to just do generic UTF-8 recovery:
try:
    recovered = text.encode('latin1').decode('utf-8')
    text = recovered
except Exception as e:
    # Manual fallback
    for k, v in mangled.items():
        text = text.replace(k, v)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
print('Done.')

