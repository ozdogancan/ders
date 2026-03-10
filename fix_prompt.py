f = open('lib/views/question_share_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# Mevcut prompt'u bul ve degistir
old_prompt = '''prompt: '\ dersinden bu soruyu coz. ONEMLI: \ dersine uygun terminoloji ve yontem kullan. SADECE gecerli JSON dondur, baska hicbir sey yazma. JSON semasi: {"summary": "Sorunun tek cumlede ozeti", "steps": [{"explanation": "Adim aciklamasi", "formula": "LaTeX formulu veya null"}], "final_answer": "Sonuc (sadece cevap, ornek: x = 3 veya B)", "tip": "Kisa motive edici cumle"} Kurallar: Turkce yaz, sade ve net ol. Ders bazli ozel kurallar: Matematik/Geometri icin her formulu LaTeX yaz ve boxed cevap ver. Fizik icin birimleri her adimda goster. Kimya icin denklemleri denkle. Biyoloji icin bilimsel terimler kullan. Turkce/Edebiyat icin dil bilgisi veya edebi sanat analizi yap. Tarih icin kronolojik sirala. Cografya icin bolge/iklim iliskisi kur. Felsefe icin akimlari belirt. Ingilizce icin grammar kuralini formul gibi goster. Her adimi ayri step olarak yaz, 1-2 cumle yeterli. Formuller MUTLAKA LaTeX formatinda olsun. Ust ifadeler: x^{2}, f^{-1}(x), (fog^{-1})^{-1}. Kesirler: \\\\frac{a}{b}, \\\\frac{n-1}{2}. Buyuk parantez: \\\\left( \\\\right). Ok isareti: \\\\implies. Carpma: \\\\cdot veya \\\\times. Dolar isareti KULLANMA. Formulleri explanation icinde YAZMA, sadece formula alanina koy. Cozumu adim adim goster, her adimda bir islem yap. Gereksiz adim ekleme, 4-6 adim ideal. final_answer kisa olsun: sadece sonuc. tip kisminda samimi ve enerjik ol, emoji kullanma.'''

new_prompt = '''prompt: '\ dersinden bu soruyu coz. SADECE gecerli JSON dondur, baska hicbir sey yazma. '
          'JSON semasi: {"summary": "Sorunun tek cumlede ozeti", "steps": [{"explanation": "Adim aciklamasi", "formula": "LaTeX formulu veya null"}], "final_answer": "Sonuc", "tip": "Kisa motive edici cumle"} '
          'GENEL KURALLAR: '
          '1. Turkce yaz, sade ve net ol. '
          '2. Her adimi ayri step yaz, 1-2 cumle yeterli. 4-6 adim ideal. '
          '3. formula alanini AKILLI kullan - sadece matematik degil, HER derste gorsel guc katan icerik koy. '
          '4. Formulleri explanation icinde YAZMA, sadece formula alanina koy. '
          '5. Dolar isareti KULLANMA. '
          '6. final_answer kisa olsun. tip samimi ve enerjik, emoji kullanma. '
          '7. Ust ifadeler: x^{2}. Kesirler: \\\\frac{a}{b}. Buyuk parantez: \\\\left( \\\\right). Ok: \\\\implies veya \\\\rightarrow. Carpma: \\\\cdot veya \\\\times. '
          ' '
          'FORMULA ALANI KULLANIM REHBERI (her ders icin): '
          'Matematik/Geometri: Her islem adimini formula alanina yaz. x^{2}+3x-4=0, A=\\\\pi r^{2}, \\\\sin 30=\\\\frac{1}{2}. Cevap: \\\\boxed{sonuc}. '
          'Fizik: Fizik formullerini yaz VE birimli hesaplari goster. F=m \\\\cdot a, v=\\\\frac{\\\\Delta x}{\\\\Delta t}, E_k=\\\\frac{1}{2}mv^{2}. Birim: \\\\text{ N}, \\\\text{ m/s}. '
          'Kimya: Denklemleri yaz. 2H_2+O_2 \\\\rightarrow 2H_2O. Mol hesabi: n=\\\\frac{m}{M}. Elektron dizilimi: 1s^{2}2s^{2}2p^{6}. '
          'Biyoloji: Surecleri formul gibi yaz. 6CO_2+6H_2O \\\\xrightarrow{isik} C_6H_{12}O_6+6O_2. Genetik: Aa \\\\times Aa \\\\rightarrow AA:Aa:aa = 1:2:1. Oranlar: \\\\frac{3}{4} baskin. '
          'Turkce: Cumle yapisi semalari. Ozne + Nesne + Yuklem. Ek analizi: gel-ecek-ti-m seklinde parcala. Ses olaylari: formul olarak goster. '
          'Edebiyat: Eser bilgisi tablo seklinde. Donem \\\\rightarrow Akiim \\\\rightarrow Sanatci. Olcu: 11li hece olcusu = 6+5 veya 4+4+3. Kafiye semasi: abab, aabb. '
          'Tarih: Kronoloji ve neden-sonuc. 1071 \\\\rightarrow 1299 \\\\rightarrow 1453. Anlasma maddeleri numarali. '
          'Cografya: Koordinat, iklim ve nufus verileri. Enlem: 36-42^{\\\\circ}K, Sicaklik \\\\propto \\\\frac{1}{yukseklik}. Nufus yogunlugu: \\\\frac{N}{A}=kisi/km^{2}. '
          'Felsefe: Akimlar arasi iliski. Rasyonalizm \\\\leftrightarrow Empirizm. Filozof \\\\rightarrow Temel gorusu. '
          'Ingilizce: Grammar formuller. Present Perfect: S + have/has + V_3. If Clause Type 2: If + V_2, would + V_1. Passive: S + be + V_3 + by + O. '
          'Din Kulturu: Kavram iliskileri. Farz \\\\supset Vacip \\\\supset Sunnet. Ibadet turleri ve sartlari. '
          ' '
          'ONEMLI: Her adimda formula alanini MUTLAKA kullan (null birakma). Formulun olmadigi adimda bile anahtar kavramlari veya iliskileri LaTeX ile gorsellestir.'''

c = c.replace(old_prompt, new_prompt)

f = open('lib/views/question_share_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('Madde 8: Kapsamli prompt - OK')
