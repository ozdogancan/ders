p = 'lib/views/main_shell.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace("import 'home_screen.dart';", "import 'scan_home_screen.dart';")
c = c.replace("return const HomeScreen();", "return const ScanHomeScreen();")
with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done - MainShell updated')
