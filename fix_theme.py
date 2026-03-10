f = open('lib/core/theme/app_theme.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

c = c.replace('filled: true,', 'filled: false,')
c = c.replace('fillColor: AppColors.grey100,', 'fillColor: Colors.transparent,')

f = open('lib/core/theme/app_theme.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('inputDecorationTheme fillColor fix - OK')
