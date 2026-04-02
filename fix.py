p = 'lib/stores/question_store.dart'
with open(p, 'r', encoding='utf-8') as f:
    content = f.read()
old = '    _questions.clear();'
new = "    debugPrint('loadFromSupabase: uid=\');\n    _questions.clear();"
content = content.replace(old, new, 1)
with open(p, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done')
