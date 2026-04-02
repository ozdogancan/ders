# -*- coding: utf-8 -*-
p = 'lib/views/auth_common.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Feature strip
c = c.replace("'10 \u00fccretsiz kredi'", "'\u00dccretsiz mekan analizi'")
c = c.replace("'9 bran\u015f'", "'Stil tespiti'")
c = c.replace("'AI \u00e7\u00f6z\u00fcm'", "'Tasar\u0131mc\u0131 e\u015fle\u015ftir'")

# 2. URL guncelle
c = c.replace("https://www.koalatutor.com/terms", "https://www.koalatutor.com/terms")
c = c.replace("https://www.koalatutor.com/privacy", "https://www.koalatutor.com/privacy")

# 3. Privacy icerigi guncelle
c = c.replace("yapay zeka destekli bir e\u011fitim uygulamas\u0131d\u0131r", "yapay zeka destekli bir mekan analiz uygulamas\u0131d\u0131r")
c = c.replace("Soru foto\u011fraflar\u0131: \u00c7\u00f6z\u00fcm i\u00e7in g\u00f6nderdi\u011finiz soru foto\u011fraflar\u0131", "Mekan foto\u011fraflar\u0131: Analiz i\u00e7in g\u00f6nderdi\u011finiz mekan foto\u011fraflar\u0131")
c = c.replace("Sohbet mesajlar\u0131: AI \u00f6\u011fretmen ile yapt\u0131\u011f\u0131n\u0131z yaz\u0131\u015fmalar", "Sohbet mesajlar\u0131: AI dan\u0131\u015fman ile yapt\u0131\u011f\u0131n\u0131z yaz\u0131\u015fmalar")
c = c.replace("Soru \u00e7\u00f6z\u00fcm hizmeti sunmak ve AI destekli \u00f6\u011fretim sa\u011flamak", "Mekan analiz hizmeti sunmak ve AI destekli tasar\u0131m \u00f6nerileri sa\u011flamak")
c = c.replace("soru foto\u011fraf\u0131 \u00e7ekmeniz i\u00e7in", "mekan foto\u011fraf\u0131 \u00e7ekmeniz i\u00e7in")
c = c.replace("Kamera yaln\u0131zca siz aktif olarak foto\u011fraf \u00e7ekti\u011finizde kullan\u0131l\u0131r. Kamera izni olmadan da galeriden foto\u011fraf se\u00e7erek soru g\u00f6nderebilirsiniz.", "Kamera yaln\u0131zca siz aktif olarak foto\u011fraf \u00e7ekti\u011finizde kullan\u0131l\u0131r. Kamera izni olmadan da galeriden foto\u011fraf se\u00e7erek mekan analizi yapabilirsiniz.")
c = c.replace("Google Gemini AI: Yapay zeka destekli soru \u00e7\u00f6z\u00fcm motoru", "Google Gemini AI: Yapay zeka destekli mekan analiz motoru")

# 4. Terms icerigi guncelle
c = c.replace("Koala, yapay zeka destekli bir e\u011fitim uygulamas\u0131d\u0131r. Kullan\u0131c\u0131lar soru foto\u011fraf\u0131 \u00e7ekerek ad\u0131m ad\u0131m \u00e7\u00f6z\u00fcm alabilir. Uygulama 9 farkl\u0131 bran\u015fta AI destekli \u00f6\u011fretim hizmeti sunar.", "Koala, yapay zeka destekli bir mekan analiz uygulamas\u0131d\u0131r. Kullan\u0131c\u0131lar mekan foto\u011fraf\u0131 \u00e7ekerek stil analizi, renk paleti ve tasar\u0131mc\u0131 e\u015fle\u015ftirme hizmeti alabilir.")
c = c.replace("Her soru \u00e7\u00f6z\u00fcm\u00fc 1 kredi harcar", "Her mekan analizi 1 kredi harcar")
c = c.replace("Uygulamay\u0131 yaln\u0131zca e\u011fitim ama\u00e7l\u0131 kullanabilirsiniz.", "Uygulamay\u0131 yaln\u0131zca ki\u015fisel mekan analizi ama\u00e7l\u0131 kullanabilirsiniz.")
c = c.replace("Koala bir e\u011fitim yard\u0131mc\u0131s\u0131d\u0131r, profesyonel \u00f6\u011fretmenin yerini almaz. AI \u00e7\u00f6z\u00fcmlerinin do\u011frulu\u011fu garanti edilmez.", "Koala bir mekan analiz asistan\u0131d\u0131r, profesyonel i\u00e7 mimar\u0131n yerini almaz. AI \u00f6nerilerinin do\u011frulu\u011fu garanti edilmez.")
c = c.replace("Koala - AI \u00d6\u011fretmen", "Koala by evlumba")

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done - auth_common metinleri guncellendi')
