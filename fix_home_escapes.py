p = 'lib/views/scan_home_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('\\$', '$')
c = c.replace("\\u015f", "\u015f")
c = c.replace("\\u0131", "\u0131")
c = c.replace("\\u00e7", "\u00e7")
c = c.replace("\\u011f", "\u011f")
c = c.replace("\\u00c7", "\u00c7")
c = c.replace("\\u015e", "\u015e")
c = c.replace("\\ud83c\\udfe0", "\U0001f3e0")
c = c.replace("\\ud83c\\udf73", "\U0001f373")
c = c.replace("\\ud83d\\udecf", "\U0001f6cf")
c = c.replace("\\ud83d\\udebf", "\U0001f6bf")
c = c.replace("\\ud83d\\udcbc", "\U0001f4bc")
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done - escapes fixed')
