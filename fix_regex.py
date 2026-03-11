f = open('lib/stores/question_store.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

# Mevcut try-catch blogunun icindeki regex'i daha basit ve guvenilir olanla degistir
old_regex = "jsonStr = jsonStr.replaceAllMapped("
idx = c.find(old_regex)
if idx > 0:
    # Tum regex blogu bul
    end_idx = c.find(');', idx) + 2
    old_block = c[idx:end_idx]
    print(f'Eski regex blogu: {old_block[:80]}...')
    
    # Daha basit yaklasim: once tum backslash'leri cikar, sonra yeniden ekle
    new_block = """// Basit yaklasim: JSON icindeki LaTeX backslash'lerini duzelt
        jsonStr = jsonStr.replaceAll(RegExp(r'\\\\(?![\\\\"/bfnrtu])'), '\\\\\\\\');"""
    
    c = c[:idx] + new_block + c[end_idx:]
    print('Regex basitlestirildi')
else:
    print('replaceAllMapped bulunamadi')

f = open('lib/stores/question_store.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('DONE')
