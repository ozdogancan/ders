# -*- coding: utf-8 -*-
p = 'lib/views/auth_entry_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Baslik
c = c.replace("Koala'ya Ho\u015fgeldin", "Koala'ya Ho\u015fgeldin")  # ayni kalabilir
c = c.replace("Sorunun foto\u011fraf\u0131n\u0131 \u00e7ek, Koala ad\u0131m ad\u0131m \u00e7\u00f6zs\u00fcn.", "Mekan\u0131n\u0131 tara, stilini ke\u015ffet, do\u011fru tasar\u0131mc\u0131yla e\u015fle\u015f.")
c = c.replace("Kald\u0131\u011f\u0131n yerden devam et.", "Mekan analizine kald\u0131\u011f\u0131n yerden devam et.")

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done - auth_entry_screen metinleri guncellendi')
