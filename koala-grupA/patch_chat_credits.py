import sys

p = 'lib/views/chat_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

changes = 0

# PATCH 1: Remove credits badge from chat AppBar actions
# Keep only the favorite button, remove the Padding with credits
old_actions = """          // Favorite toggle
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
          Padding(padding: const EdgeInsets.only(right: 12),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(15), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF6366F1)),
                const SizedBox(width: 3),
                Text(_credits < 0 ? '' : '$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 13)),
              ]))),"""

new_actions = """          // Favorite toggle
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
          const SizedBox(width: 8),"""

if old_actions in c:
    c = c.replace(old_actions, new_actions, 1)
    changes += 1
    print("PATCH 1 OK: Removed duplicate credits badge from chat AppBar")
else:
    print("PATCH 1 SKIP: Pattern not found (may already be applied)")

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)

print(f"\nDone! {changes} patches applied to chat_screen.dart")
