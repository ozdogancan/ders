import sys

p = 'lib/views/home_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

# Add import for CreditStoreScreen if not present
if "import 'credit_store_screen.dart';" not in c:
    c = c.replace(
        "import 'profile_screen.dart';",
        "import 'profile_screen.dart';\nimport 'credit_store_screen.dart';",
        1
    )
    print("Added CreditStoreScreen import")

changes = 0

# There are multiple credit badge instances in the file. We need to wrap each one with GestureDetector.
# Pattern: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
#   decoration: BoxDecoration(gradient: ... borderRadius: ... border: ...),
#   child: Row(... bolt icon + credits text ...))

# We'll replace each standalone credits Container with a GestureDetector-wrapped version.
# The credits container pattern appears in: _buildSplitNavBar, _buildNormalView

old_credit = """Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(15), const Color(0xFF8B5CF6).withAlpha(10)]),
            borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6366F1)), const SizedBox(width: 4),
            Text('$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 14)),
          ]))"""

new_credit = """GestureDetector(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreditStoreScreen()));
            _loadCredits();
          },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(15), const Color(0xFF8B5CF6).withAlpha(10)]),
              borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6366F1)), const SizedBox(width: 4),
              Text('$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 14)),
            ])))"""

count = c.count(old_credit)
if count > 0:
    c = c.replace(old_credit, new_credit)
    changes += count
    print(f"PATCH OK: Wrapped {count} credit badges with GestureDetector -> CreditStoreScreen")
else:
    # Try alternative pattern (with different whitespace)
    old_credit2 = """Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(15), const Color(0xFF8B5CF6).withAlpha(10)]),
                borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6366F1)),
                const SizedBox(width: 4),
                Text('$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 14)),
              ]))"""

    new_credit2 = """GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreditStoreScreen()));
                _loadCredits();
              },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(15), const Color(0xFF8B5CF6).withAlpha(10)]),
                  borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6366F1)),
                  const SizedBox(width: 4),
                  Text('$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 14)),
                ])))"""

    count2 = c.count(old_credit2)
    if count2 > 0:
        c = c.replace(old_credit2, new_credit2)
        changes += count2
        print(f"PATCH OK (alt pattern): Wrapped {count2} credit badges")
    else:
        print("PATCH SKIP: Credit badge pattern not found")

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)

print(f"\nDone! {changes} credit badges made clickable in home_screen.dart")
