import sys

p = 'lib/views/chat_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

changes = 0

# PATCH 1: Add markRead + touchInteraction in initState after Analytics.chatOpened
old1 = "Analytics.chatOpened(widget.questionId, _q?.subject ?? '');"
new1 = """Analytics.chatOpened(widget.questionId, _q?.subject ?? '');
    QuestionStore.instance.markRead(widget.questionId);
    QuestionStore.instance.touchInteraction(widget.questionId);"""
if old1 in c:
    c = c.replace(old1, new1, 1)
    changes += 1
    print("PATCH 1 OK: markRead + touchInteraction added")
else:
    print("PATCH 1 SKIP: Already applied or pattern not found")

# PATCH 2: Add favorite toggle button in AppBar actions
old2 = """actions: [
          Padding(padding: const EdgeInsets.only(right: 12),"""
new2 = """actions: [
          // Favorite toggle
          Builder(builder: (_) {
            final qq = _q;
            if (qq == null) return const SizedBox.shrink();
            return IconButton(
              onPressed: () {
                QuestionStore.instance.toggleFavorite(widget.questionId);
                setState(() {});
              },
              icon: Icon(
                qq.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: qq.isFavorite ? const Color(0xFFFBBF24) : Colors.grey.shade400,
                size: 22,
              ),
            );
          }),
          Padding(padding: const EdgeInsets.only(right: 12),"""
if old2 in c:
    c = c.replace(old2, new2, 1)
    changes += 1
    print("PATCH 2 OK: Favorite button added to AppBar")
else:
    print("PATCH 2 SKIP: Already applied or pattern not found")

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)

print(f"\nDone! {changes} patches applied.")
