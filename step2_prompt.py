f = open('lib/views/question_share_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# Mevcut _solveInBackground icindeki prompt'u bul
old_prompt_start = "prompt: '"
old_prompt_end = "emoji kullanma.');"

idx_s = c.find(old_prompt_start, c.find('_solveInBackground'))
idx_e = c.find(old_prompt_end, idx_s) + len(old_prompt_end)

old_prompt = c[idx_s:idx_e]
print(f'Eski prompt bulundu: {len(old_prompt)} karakter')

new_prompt = "prompt: subject == 'Matematik' || subject == 'Geometri' ? _getMathPrompt(subject, bytes) : _getGeneralPrompt(subject));"

c = c[:idx_s] + new_prompt + c[idx_e:]

# _getMathPrompt ve _getGeneralPrompt fonksiyonlarini ekle
# _showNoCredit'den hemen once ekle
insert_point = c.find('Future<void> _showNoCredit')

math_funcs = '''
  String _getMathPrompt(String subject, dynamic bytes) {
    return '\x24subject soruyu coz. SADECE JSON dondur. '
      'Sema: {"question_type":"hesaplama|problem|grafik|ispat","summary":"ozet",'
      '"given":["veri1"] veya null,"find":"istenen" veya null,"modeling":"LaTeX denklem" veya null,'
      '"steps":[{"explanation":"ne yaptik","reasoning":"NEDEN yaptik","formula":"LaTeX","is_critical":false}],'
      '"final_answer":"sonuc","golden_rule":"bu tur sorularda ezberle kurali","tip":"motivasyon"} '
      'KURALLAR: Turkce yaz. 4-6 adim. HER adimda reasoning yaz. '
      'Tam 1 adim is_critical:true sec (kilit nokta). golden_rule zorunlu. '
      'problem tipinde given/find/modeling doldur. Diger tiplerde null birak. '
      'LaTeX: x^{2}, \\\\frac{a}{b}, \\\\implies, \\\\cdot, \\\\times, \\\\boxed{sonuc}. '
      'Dolar isareti KULLANMA. Formulleri explanation icinde YAZMA, formula alanina koy. '
      'final_answer kisa. tip samimi, emoji kullanma.';
  }

  String _getGeneralPrompt(String subject) {
    return '\x24subject soruyu coz. SADECE JSON dondur. '
      'Sema: {"question_type":"genel","summary":"ozet",'
      '"steps":[{"explanation":"ne yaptik","reasoning":"neden yaptik","formula":"LaTeX veya null","is_critical":false}],'
      '"final_answer":"sonuc","golden_rule":"temel kural","tip":"motivasyon"} '
      'KURALLAR: Turkce yaz. 4-6 adim. HER adimda reasoning yaz. 1 adim is_critical:true. golden_rule zorunlu. '
      'LaTeX: x^{2}, \\\\frac{a}{b}. Dolar isareti KULLANMA. formula alanina koy.';
  }

'''

c = c[:insert_point] + math_funcs + c[insert_point:]

f = open('lib/views/question_share_screen.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('Adim 2: Prompt guncellendi')
