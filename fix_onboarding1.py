import re

p = 'lib/views/onboarding_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Sayfa verileri (_PD) degistir
content = content.replace(
    "_PD('Merhaba,\\nben Koala!', 'Hangi konuda tak\u0131l\u0131rsan tak\u0131l, ad\u0131m ad\u0131m \u00e7\u00f6z\u00fcm \u00fcretiyorum.', const Color(0xFF6265E8), const Color(0xFF5558DF), 0)",
    "_PD('Merhaba,\\nben Koala!', 'Odan\u0131n foto\u011fraf\u0131n\u0131 \u00e7ek, stilini anla, ilham bul.', const Color(0xFF6C5CE7), const Color(0xFF5A4BD6), 0)"
)

content = content.replace(
    "_PD('\u00c7ek, g\u00f6nder, anla', 'Sorunun foto\u011fraf\u0131n\u0131 \u00e7ek. Koala ad\u0131m ad\u0131m \u00e7\u00f6zs\u00fcn.', const Color(0xFF38BDF8), const Color(0xFF22D3EE), 1)",
    "_PD('\u00c7ek, tara, ke\u015ffet', 'Mekan\u0131n\u0131n foto\u011fraf\u0131n\u0131 \u00e7ek.\\nKoala stilini analiz etsin.', const Color(0xFF00B894), const Color(0xFF00A381), 1)"
)

# 2. Feature chip'leri degistir
content = content.replace(
    "const _FeatureChip(Icons.camera_alt, 'Foto ile soru \u00e7\u00f6z')",
    "const _FeatureChip(Icons.camera_alt, 'Foto ile analiz')"
)
content = content.replace(
    "const _FeatureChip(Icons.route, 'Ad\u0131m ad\u0131m \u00e7\u00f6z\u00fcm')",
    "const _FeatureChip(Icons.home_rounded, 'Stil tespiti')"
)
content = content.replace(
    "const _FeatureChip(Icons.school, '9 bran\u015f')",
    "const _FeatureChip(Icons.people_rounded, 'Tasar\u0131mc\u0131 e\u015fle\u015ftir')"
)

with open(p, 'w', encoding='utf-8') as f:
    f.write(content)

print('Done - metinler ve chipler guncellendi')
