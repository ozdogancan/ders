f = open('web/index.html', 'r', encoding='utf-8')
c = f.read()
f.close()

# Chrome autofill arka plan rengini kaldir
if 'autofill' not in c:
    c = c.replace('</head>', '''  <style>
    input:-webkit-autofill,
    input:-webkit-autofill:hover,
    input:-webkit-autofill:focus {
      -webkit-box-shadow: 0 0 0 1000px white inset !important;
      background-color: white !important;
    }
    input {
      background-color: transparent !important;
    }
    flt-glass-pane {
      background-color: white !important;
    }
  </style>
</head>''')

f = open('web/index.html', 'w', encoding='utf-8')
f.write(c)
f.close()
print('Chrome autofill fix - OK')
