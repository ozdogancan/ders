f = open('lib/stores/question_store.dart', 'r', encoding='utf-8')
c = f.read()
f.close()

old = '''void setWaitingAnswer(String id) {
    final idx = _questions.indexWhere((q) => q.id == id);
    if (idx < 0) return;
    _questions[idx] = _questions[idx].copyWith(status: QStatus.waitingAnswer);
    notifyListeners();
  }'''

new = '''void setWaitingAnswer(String id) {
    final q = getById(id);
    if (q == null) return;
    q.status = QStatus.waitingAnswer;
    notifyListeners();
  }'''

c = c.replace(old, new)

f = open('lib/stores/question_store.dart', 'w', encoding='utf-8')
f.write(c)
f.close()
print('Fixed setWaitingAnswer - OK')
