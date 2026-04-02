p = 'lib/models/scan_analysis.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace("\\$h", "$h")
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done')
