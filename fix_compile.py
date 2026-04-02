#!/usr/bin/env python3
"""Fix compile errors after guided flow generation"""
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# FIX 1: flow_models.dart — lambda return in const context
# The issue: map().toList() with 'return' inside FlowStep widgetData
# Fix: use arrow syntax instead
# ═══════════════════════════════════════════════════════════
fpath = os.path.join(BASE, "lib", "models", "flow_models.dart")
with open(fpath, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the problematic lambda patterns
content = content.replace(
    """'items': kStyleOptions.map((s) => {
              return {'id': s.id, 'label': s.label, 'image': s.image};
            }).toList(),""",
    """'items': kStyleOptions.map((s) =>
              <String, dynamic>{'id': s.id, 'label': s.label, 'image': s.image}).toList(),"""
)

# Also add roomType back to FlowState for backward compat
content = content.replace(
    """class FlowState {
  final FlowType type;
  final String? initialParam; // ilk parametre (stil adı, oda tipi vs.)
  int currentStep;
  final Map<String, dynamic> collected;
  final List<FlowStep> steps;

  FlowState({
    required this.type,
    this.initialParam,
    this.currentStep = 0,
    Map<String, dynamic>? collected,
    List<FlowStep>? steps,
  })  : collected = collected ?? {},
        steps = steps ?? [];""",
    """class FlowState {
  final FlowType type;
  final String? initialParam; // ilk parametre (stil adı, oda tipi vs.)
  final String roomType; // backward compat
  int currentStep;
  final Map<String, dynamic> collected;
  final List<FlowStep> steps;

  FlowState({
    required this.type,
    this.initialParam,
    this.roomType = 'salon',
    this.currentStep = 0,
    Map<String, dynamic>? collected,
    List<FlowStep>? steps,
  })  : collected = collected ?? {},
        steps = steps ?? [];"""
)

with open(fpath, 'w', encoding='utf-8') as f:
    f.write(content)
print(f"  ✅ Fixed flow_models.dart (lambda syntax + roomType)")

# ═══════════════════════════════════════════════════════════
# FIX 2: chat_detail_screen.dart — update buildRoomRenovation call
# Old: FlowBuilder.buildRoomRenovation(room)
# New: FlowBuilder.buildRoomRenovation()  (no args)
# ═══════════════════════════════════════════════════════════
fpath2 = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")
if os.path.exists(fpath2):
    with open(fpath2, 'r', encoding='utf-8') as f:
        content2 = f.read()

    # Fix: remove the argument from buildRoomRenovation calls
    content2 = re.sub(
        r'FlowBuilder\.buildRoomRenovation\([^)]+\)',
        'FlowBuilder.buildRoomRenovation()',
        content2
    )

    with open(fpath2, 'w', encoding='utf-8') as f:
        f.write(content2)
    print(f"  ✅ Fixed chat_detail_screen.dart (buildRoomRenovation args)")
else:
    print(f"  ⚠️  chat_detail_screen.dart not found, skipping")

print()
print("Done! Run: flutter run -d chrome")
