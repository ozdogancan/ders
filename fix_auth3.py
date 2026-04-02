# -*- coding: utf-8 -*-
p = 'lib/views/auth_entry_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

# Baslik altina evlumba notu ekle - "Kaldigin yerden devam et." satirindan sonra
old_sub = "                                    : 'Mekan analizine kald\u0131\u011f\u0131n yerden devam et.',"
if old_sub not in c:
    old_sub = "                                    : 'Mekan analizine kald\u0131\u011f\u0131n yerden devam et.',"

# Feature strip'in ustune evlumba notu ekleyelim - footer animasyonundan once
old_feature = "// Feature dots"
new_feature = """// evlumba notu
                        FadeSlideIn(
                          animation: featureAnim,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0EEFF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE0D4FF)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: const <Widget>[
                                Icon(Icons.link_rounded, size: 14, color: Color(0xFF6C63FF)),
                                SizedBox(width: 8),
                                Flexible(child: Text(
                                  'evlumba hesab\u0131n varsa ayn\u0131 Google hesab\u0131yla giri\u015f yap',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6C63FF)),
                                  textAlign: TextAlign.center,
                                )),
                              ],
                            ),
                          ),
                        ),

                        // Feature dots"""

c = c.replace(old_feature, new_feature)

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done - evlumba notu eklendi')
