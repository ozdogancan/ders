f = open('lib/stores/question_store.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

changes = 0

# 1a. SolutionStep'e reasoning ve isCritical ekle
old1 = 'SolutionStep({required this.explanation, this.formula, this.isAnswer = false});'
new1 = 'SolutionStep({required this.explanation, this.formula, this.reasoning, this.isCritical = false, this.isAnswer = false});'
if old1 in c:
    c = c.replace(old1, new1)
    changes += 1

old1b = '  final String explanation;\n  final String? formula;\n  final bool isAnswer;'
new1b = '  final String explanation;\n  final String? formula;\n  final String? reasoning;\n  final bool isCritical;\n  final bool isAnswer;'
if 'final String? reasoning;' not in c:
    c = c.replace(old1b, new1b)
    changes += 1

old1c = "formula: (json['formula'] as String?)?.trim(),\n      isAnswer: json['is_answer'] as bool? ?? false,"
new1c = "formula: (json['formula'] as String?)?.trim(),\n      reasoning: (json['reasoning'] as String?)?.trim(),\n      isCritical: json['is_critical'] as bool? ?? false,\n      isAnswer: json['is_answer'] as bool? ?? false,"
if 'reasoning' not in c.split('SolutionStep')[1].split('class')[0]:
    c = c.replace(old1c, new1c)
    changes += 1

# 1b. StructuredAnswer'a yeni alanlar ekle
old2 = 'StructuredAnswer({required this.summary, required this.steps, required this.finalAnswer, this.tip});'
new2 = 'StructuredAnswer({required this.summary, required this.steps, required this.finalAnswer, this.tip, this.questionType, this.goldenRule, this.givenData, this.findData, this.modelEquation});'
if old2 in c:
    c = c.replace(old2, new2)
    changes += 1

old2b = '  final String? tip;\n'
new2b = '  final String? tip;\n  final String? questionType;\n  final String? goldenRule;\n  final List<String>? givenData;\n  final String? findData;\n  final String? modelEquation;\n'
if 'final String? questionType;' not in c:
    c = c.replace(old2b, new2b, 1)
    changes += 1

old2c = "tip: (json['tip'] as String?)?.trim(),\n    );"
new2c = "tip: (json['tip'] as String?)?.trim(),\n      questionType: (json['question_type'] as String?)?.trim(),\n      goldenRule: (json['golden_rule'] as String?)?.trim(),\n      givenData: json['given'] is List ? (json['given'] as List<dynamic>).map((e) => e.toString()).where((s) => s.isNotEmpty && s != 'null').toList() : null,\n      findData: (json['find'] as String?)?.trim(),\n      modelEquation: (json['modeling'] as String?)?.trim(),\n    );"
if 'questionType' not in c.split('fromJson')[1].split('}')[0]:
    c = c.replace(old2c, new2c)
    changes += 1

# 1c. LaTeX escape fix - tryParse icinde
old3 = "final decoded = jsonDecode(match.group(0)!) as Map<String, dynamic>;"
new3 = """var jsonStr = match.group(0)!;
      jsonStr = jsonStr.replaceAll(RegExp(r'[\\x00-\\x09\\x0b\\x0c\\x0e-\\x1f]'), ' ');
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        jsonStr = jsonStr.replaceAllMapped(
          RegExp(r'(?<!\\\\\\\\)\\\\\\\\(?!\\\\\\\\|"|n|t|r|u[0-9a-fA-F])'),
          (m) => '\\\\\\\\\\\\\\\\',
        );
        decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      }"""
if old3 in c:
    c = c.replace(old3, new3)
    changes += 1

c = c.replace('return StructuredAnswer.fromJson(decoded);', 'return StructuredAnswer.fromJson(decoded);')

f = open('lib/stores/question_store.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print(f'Adim 1: Model - {changes} degisiklik yapildi')
