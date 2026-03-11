f = open('lib/views/chat_screen.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

r = open('structured_card_replacement.dart', 'r', encoding='utf-8')
new_func = r.read()
r.close()

lines = new_func.split('\n')
clean_lines = [l for l in lines if not l.strip().startswith('//')]
new_func = '\n'.join(clean_lines).strip() + '\n\n'

start = c.find('Widget _structuredCard(StructuredAnswer a) {')
end = c.find('Widget _ratingWidget')
print(f'Start: {start}, End: {end}')

if start > 0 and end > start:
    c = c[:start] + new_func + '  ' + c[end:]
    f = open('lib/views/chat_screen.dart', 'w', encoding='utf-8')
    f.write(c)
    f.close()
    print('Replacement OK')
else:
    print('ERROR: fonksiyon bulunamadi')
