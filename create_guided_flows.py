#!/usr/bin/env python3
"""
Koala Guided Flow System — Complete Generator
==============================================
Her kartın arkasında zengin, interaktif UI deneyimi.
Düz text YOK — her şey widget kartlarıyla.

Dosyalar:
1. lib/models/flow_models.dart         — GÜNCELLEME (tüm flow builder'lar)
2. lib/widgets/flow_widgets.dart        — GÜNCELLEME (yeni widget'lar eklendi)
3. lib/widgets/flow_result_widgets.dart — YENİ (sonuç kartları)
4. lib/views/guided_flow_screen.dart    — YENİ (flow orkestratör ekranı)
5. lib/views/home_screen.dart           — GÜNCELLEME (kartlar flow'lara yönlendirildi)
"""

import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"

files = {}

# ═══════════════════════════════════════════════════════════════
# 1. FLOW MODELS — Tüm flow'ların step tanımları
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "models", "flow_models.dart")] = r'''/// Flow types Koala supports
enum FlowType {
  roomRenovation,   // Odanı Tara → stil seç → detay → fotoğraf → sonuç
  budgetPlan,       // Bütçe Planla → oda → bütçe → öncelik → sonuç
  designerMatch,    // Tasarımcı Bul → stil → şehir → bütçe → sonuç
  styleExplore,     // İlham kartı → stil detay → oda seç → renk → sonuç
  colorAdvice,      // Trend Renk → oda → mood → fotoğraf → sonuç
  freeChat,         // Serbest sohbet
}

/// A single step in a flow
class FlowStep {
  final String id;
  final String koalaMessage;
  final String widgetType;
  // Widget types:
  //   'room_select'    — oda tipi seçimi (ikonlu grid)
  //   'image_grid'     — görsel grid (stil seçimi)
  //   'chip_select'    — chip grupları (bütçe, öncelik vs.)
  //   'city_select'    — şehir seçimi (arama + popüler)
  //   'color_mood'     — mood/atmosfer seçimi (görsel chip)
  //   'photo_capture'  — fotoğraf çek/seç
  //   'budget_slider'  — slider + preset butonlar
  //   'style_hero'     — stil detay hero kartı
  //   'result'         — AI sonuç (loading → kartlar)
  final Map<String, dynamic> widgetData;
  final bool skippable;

  const FlowStep({
    required this.id,
    required this.koalaMessage,
    required this.widgetType,
    this.widgetData = const {},
    this.skippable = false,
  });
}

/// Current state of an active flow
class FlowState {
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
        steps = steps ?? [];

  FlowStep? get current => currentStep < steps.length ? steps[currentStep] : null;
  bool get isComplete => currentStep >= steps.length;
  double get progress => steps.isEmpty ? 0 : (currentStep / steps.length).clamp(0.0, 1.0);
}

// ═══════════════════════════════════════════════════════════
// Room data — oda tipleri (tüm flow'larda ortak)
// ═══════════════════════════════════════════════════════════
class RoomOption {
  final String id;
  final String label;
  final String emoji;
  const RoomOption(this.id, this.label, this.emoji);
}

const kRoomOptions = [
  RoomOption('salon', 'Salon', '🛋️'),
  RoomOption('yatak_odasi', 'Yatak Odası', '🛏️'),
  RoomOption('mutfak', 'Mutfak', '🍳'),
  RoomOption('banyo', 'Banyo', '🚿'),
  RoomOption('cocuk_odasi', 'Çocuk Odası', '🧸'),
  RoomOption('ofis', 'Ev Ofisi', '💻'),
  RoomOption('balkon', 'Balkon', '🌿'),
  RoomOption('antre', 'Antre', '🚪'),
];

String roomLabel(String type) {
  const map = {
    'salon': 'salon', 'mutfak': 'mutfak', 'yatak_odasi': 'yatak odası',
    'banyo': 'banyo', 'balkon': 'balkon', 'cocuk_odasi': 'çocuk odası',
    'ofis': 'ofis', 'antre': 'antre',
  };
  return map[type] ?? type;
}

// ═══════════════════════════════════════════════════════════
// Style data — stil seçenekleri
// ═══════════════════════════════════════════════════════════
class StyleOption {
  final String id;
  final String label;
  final String image;
  const StyleOption(this.id, this.label, this.image);
}

const kStyleOptions = [
  StyleOption('japandi', 'Japandi',
    'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=400&q=80'),
  StyleOption('scandinavian', 'Skandinav',
    'https://images.unsplash.com/photo-1505691938895-1758d7feb511?auto=format&fit=crop&w=400&q=80'),
  StyleOption('modern', 'Modern',
    'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?auto=format&fit=crop&w=400&q=80'),
  StyleOption('bohemian', 'Bohem',
    'https://images.unsplash.com/photo-1540518614846-7eded433c457?auto=format&fit=crop&w=400&q=80'),
  StyleOption('industrial', 'Endüstriyel',
    'https://images.unsplash.com/photo-1618221195710-dd6b41faaea6?auto=format&fit=crop&w=400&q=80'),
  StyleOption('rustic', 'Rustik',
    'https://images.unsplash.com/photo-1556909172-54557c7e4fb7?auto=format&fit=crop&w=400&q=80'),
  StyleOption('minimalist', 'Minimalist',
    'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=400&q=80'),
  StyleOption('classic', 'Klasik',
    'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=400&q=80'),
];

// ═══════════════════════════════════════════════════════════
// FLOW BUILDERS
// ═══════════════════════════════════════════════════════════
class FlowBuilder {

  // ─── 1. ODANI TARA (Room Renovation) ───
  static FlowState buildRoomRenovation() {
    return FlowState(
      type: FlowType.roomRenovation,
      steps: [
        const FlowStep(
          id: 'room_select',
          koalaMessage: 'Hangi odanı yenilemek istiyorsun? 🏠',
          widgetType: 'room_select',
          widgetData: {},
        ),
        FlowStep(
          id: 'style_pick',
          koalaMessage: 'Hangi tarza daha yakınsın? Bir veya iki tanesini seç 👆',
          widgetType: 'image_grid',
          widgetData: {
            'columns': 2,
            'maxSelect': 2,
            'items': kStyleOptions.map((s) => {
              return {'id': s.id, 'label': s.label, 'image': s.image};
            }).toList(),
          },
        ),
        const FlowStep(
          id: 'details',
          koalaMessage: 'Harika seçim! Birkaç detay daha ✨',
          widgetType: 'chip_select',
          widgetData: {
            'groups': [
              {
                'label': 'Bütçen ne kadar?',
                'key': 'budget',
                'single': true,
                'chips': [
                  {'id': 'low', 'label': '💚 10-30K TL'},
                  {'id': 'mid', 'label': '💛 30-60K TL'},
                  {'id': 'high', 'label': '🔥 60K+ TL'},
                ],
              },
              {
                'label': 'Önceliğin ne?',
                'key': 'priority',
                'single': false,
                'chips': [
                  {'id': 'color', 'label': '🎨 Renk'},
                  {'id': 'furniture', 'label': '🛋 Mobilya'},
                  {'id': 'lighting', 'label': '💡 Aydınlatma'},
                  {'id': 'all', 'label': '✨ Komple'},
                ],
              },
            ],
          },
        ),
        const FlowStep(
          id: 'photo',
          koalaMessage: 'Fotoğrafını görürsem çok daha isabetli öneriler verebilirim 📸',
          widgetType: 'photo_capture',
          widgetData: {'hint': 'Mevcut oda fotoğrafını çek'},
          skippable: true,
        ),
        const FlowStep(
          id: 'result',
          koalaMessage: 'İşte sana özel planın! 🐨',
          widgetType: 'result',
          widgetData: {'resultType': 'room_renovation'},
        ),
      ],
    );
  }

  // ─── 2. BÜTÇE PLANLA ───
  static FlowState buildBudgetPlan() {
    return FlowState(
      type: FlowType.budgetPlan,
      steps: [
        const FlowStep(
          id: 'room_select',
          koalaMessage: 'Hangi oda için bütçe planlayalım? 🏠',
          widgetType: 'room_select',
          widgetData: {},
        ),
        const FlowStep(
          id: 'budget',
          koalaMessage: 'Bütçeni belirleyelim 💰',
          widgetType: 'budget_slider',
          widgetData: {
            'min': 5000,
            'max': 200000,
            'initial': 40000,
            'presets': [
              {'label': '💚 10-30K', 'value': 20000},
              {'label': '💛 30-60K', 'value': 45000},
              {'label': '🔥 60-100K', 'value': 80000},
              {'label': '💎 100K+', 'value': 150000},
            ],
          },
        ),
        const FlowStep(
          id: 'priority',
          koalaMessage: 'Neye öncelik verelim?',
          widgetType: 'chip_select',
          widgetData: {
            'groups': [
              {
                'label': 'Önceliğin ne?',
                'key': 'priority',
                'single': false,
                'chips': [
                  {'id': 'paint', 'label': '🎨 Renk/Boya'},
                  {'id': 'furniture', 'label': '🛋 Mobilya'},
                  {'id': 'lighting', 'label': '💡 Aydınlatma'},
                  {'id': 'textile', 'label': '🧵 Tekstil'},
                  {'id': 'all', 'label': '✨ Komple Yenileme'},
                ],
              },
            ],
          },
        ),
        const FlowStep(
          id: 'result',
          koalaMessage: 'İşte bütçe planın! 💰',
          widgetType: 'result',
          widgetData: {'resultType': 'budget_plan'},
        ),
      ],
    );
  }

  // ─── 3. TASARIMCI BUL ───
  static FlowState buildDesignerMatch() {
    return FlowState(
      type: FlowType.designerMatch,
      steps: [
        FlowStep(
          id: 'style_pick',
          koalaMessage: 'Hangi tarz sana yakın? 🎨',
          widgetType: 'image_grid',
          widgetData: {
            'columns': 2,
            'maxSelect': 2,
            'items': kStyleOptions.map((s) => {
              return {'id': s.id, 'label': s.label, 'image': s.image};
            }).toList(),
          },
        ),
        const FlowStep(
          id: 'city',
          koalaMessage: 'Hangi şehirdesin? 📍',
          widgetType: 'city_select',
          widgetData: {
            'popular': ['İstanbul', 'Ankara', 'İzmir', 'Antalya', 'Bursa', 'Konya'],
          },
        ),
        const FlowStep(
          id: 'budget',
          koalaMessage: 'Tasarımcı bütçen ne kadar?',
          widgetType: 'chip_select',
          widgetData: {
            'groups': [
              {
                'label': 'Bütçe aralığın?',
                'key': 'budget',
                'single': true,
                'chips': [
                  {'id': 'low', 'label': '💚 10-25K TL'},
                  {'id': 'mid', 'label': '💛 25-50K TL'},
                  {'id': 'high', 'label': '🔥 50K+ TL'},
                ],
              },
            ],
          },
        ),
        const FlowStep(
          id: 'result',
          koalaMessage: 'İşte sana en uygun tasarımcılar! ✨',
          widgetType: 'result',
          widgetData: {'resultType': 'designer_match'},
        ),
      ],
    );
  }

  // ─── 4. STİL KEŞFET (İlham kartı tıklandığında) ───
  static FlowState buildStyleExplore(String styleName) {
    return FlowState(
      type: FlowType.styleExplore,
      initialParam: styleName,
      steps: [
        FlowStep(
          id: 'style_hero',
          koalaMessage: '$styleName tarzını keşfediyorsun 🎨',
          widgetType: 'style_hero',
          widgetData: {
            'styleName': styleName,
          },
        ),
        const FlowStep(
          id: 'room_select',
          koalaMessage: 'Bu stili hangi odana uygulamak istersin?',
          widgetType: 'room_select',
          widgetData: {},
        ),
        const FlowStep(
          id: 'color_mood',
          koalaMessage: 'Nasıl bir atmosfer istiyorsun? 🌈',
          widgetType: 'color_mood',
          widgetData: {
            'moods': [
              {'id': 'warm', 'label': 'Sıcak & Samimi', 'emoji': '☀️', 'colors': ['#E8A87C', '#D27D2D', '#C4704A']},
              {'id': 'cool', 'label': 'Ferah & Serin', 'emoji': '❄️', 'colors': ['#85B7EB', '#5DCAA5', '#8B9E6B']},
              {'id': 'energetic', 'label': 'Enerjik', 'emoji': '⚡', 'colors': ['#EF4444', '#F59E0B', '#8B5CF6']},
              {'id': 'calm', 'label': 'Huzurlu', 'emoji': '🧘', 'colors': ['#E8D5C4', '#D4C5B0', '#B8C5B0']},
            ],
          },
        ),
        const FlowStep(
          id: 'result',
          koalaMessage: 'İşte sana özel stil planın! 🐨',
          widgetType: 'result',
          widgetData: {'resultType': 'style_explore'},
        ),
      ],
    );
  }

  // ─── 5. TREND RENK UYGULA ───
  static FlowState buildColorAdvice() {
    return FlowState(
      type: FlowType.colorAdvice,
      steps: [
        const FlowStep(
          id: 'room_select',
          koalaMessage: 'Hangi oda için renk önerisi istiyorsun? 🎨',
          widgetType: 'room_select',
          widgetData: {},
        ),
        const FlowStep(
          id: 'color_mood',
          koalaMessage: 'Nasıl bir atmosfer hayal ediyorsun? 🌈',
          widgetType: 'color_mood',
          widgetData: {
            'moods': [
              {'id': 'warm', 'label': 'Sıcak & Samimi', 'emoji': '☀️', 'colors': ['#E8A87C', '#D27D2D', '#C4704A']},
              {'id': 'cool', 'label': 'Ferah & Serin', 'emoji': '❄️', 'colors': ['#85B7EB', '#5DCAA5', '#8B9E6B']},
              {'id': 'energetic', 'label': 'Enerjik', 'emoji': '⚡', 'colors': ['#EF4444', '#F59E0B', '#8B5CF6']},
              {'id': 'calm', 'label': 'Huzurlu', 'emoji': '🧘', 'colors': ['#E8D5C4', '#D4C5B0', '#B8C5B0']},
            ],
          },
        ),
        const FlowStep(
          id: 'photo',
          koalaMessage: 'Mevcut odanın fotoğrafını at, renkleri odana uyarlayayım 📸',
          widgetType: 'photo_capture',
          widgetData: {'hint': 'Mevcut oda fotoğrafı'},
          skippable: true,
        ),
        const FlowStep(
          id: 'result',
          koalaMessage: 'İşte renk önerilerim! 🎨',
          widgetType: 'result',
          widgetData: {'resultType': 'color_advice'},
        ),
      ],
    );
  }
}
'''

# ═══════════════════════════════════════════════════════════════
# 2. FLOW WIDGETS — Mevcut + yeni widget'lar
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "widgets", "flow_widgets.dart")] = r'''import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/flow_models.dart';

const _accent = Color(0xFF6C5CE7);
const _accentLight = Color(0xFFF3F0FF);
const _R = 16.0;

// ═══════════════════════════════════════════════════════════
// ROOM SELECT — ikonlu oda grid'i
// ═══════════════════════════════════════════════════════════

class FlowRoomSelect extends StatelessWidget {
  const FlowRoomSelect({super.key, required this.onSelect});
  final void Function(String roomId) onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: kRoomOptions.map((room) {
        return GestureDetector(
          onTap: () => onSelect(room.id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_R),
              color: _accentLight,
              border: Border.all(color: const Color(0xFFEDEAF5)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(room.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 6),
                Text(room.label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A4458))),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// IMAGE GRID — stil seçimi (2 columns)
// ═══════════════════════════════════════════════════════════

class FlowImageGrid extends StatefulWidget {
  const FlowImageGrid({super.key, required this.data, required this.onDone});
  final Map<String, dynamic> data;
  final void Function(List<String> selectedIds) onDone;

  @override
  State<FlowImageGrid> createState() => _FlowImageGridState();
}

class _FlowImageGridState extends State<FlowImageGrid> {
  final Set<String> _selected = {};
  int get _maxSelect => widget.data['maxSelect'] as int? ?? 2;
  List<dynamic> get _items => widget.data['items'] as List? ?? [];

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < _maxSelect) {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8, crossAxisSpacing: 8,
        childAspectRatio: 0.85,
        children: _items.map((item) {
          final id = item['id'] as String;
          final label = item['label'] as String;
          final image = item['image'] as String;
          final on = _selected.contains(id);

          return GestureDetector(
            onTap: () => _toggle(id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_R),
                border: Border.all(color: on ? _accent : Colors.transparent, width: on ? 3 : 0),
              ),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(on ? 13 : _R),
                  child: CachedNetworkImage(imageUrl: image, fit: BoxFit.cover,
                    width: double.infinity, height: double.infinity,
                    placeholder: (_, __) => Container(color: const Color(0xFFF3F1FA)),
                    errorWidget: (_, __, ___) => Container(color: const Color(0xFFF3F1FA)))),
                Container(decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(on ? 13 : _R),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                    stops: const [0.5, 1]))),
                Positioned(bottom: 10, left: 10,
                  child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
                if (on) Positioned(top: 8, right: 8,
                  child: Container(width: 26, height: 26,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: _accent),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 16))),
              ]),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton(
          onPressed: _selected.isNotEmpty ? () => widget.onDone(_selected.toList()) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent, disabledBackgroundColor: _accent.withOpacity(0.3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          child: Text(
            _selected.isEmpty ? 'Bir stil seç' : 'Devam (${_selected.length} seçildi)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════
// CHIP SELECT — bütçe, öncelik vs.
// ═══════════════════════════════════════════════════════════

class FlowChipSelect extends StatefulWidget {
  const FlowChipSelect({super.key, required this.data, required this.onDone});
  final Map<String, dynamic> data;
  final void Function(Map<String, dynamic> selections) onDone;
  @override
  State<FlowChipSelect> createState() => _FlowChipSelectState();
}

class _FlowChipSelectState extends State<FlowChipSelect> {
  final Map<String, dynamic> _selections = {};
  List<dynamic> get _groups => widget.data['groups'] as List? ?? [];

  bool get _allFilled {
    for (final g in _groups) {
      final key = g['key'] as String;
      if (_selections[key] == null) return false;
      if (_selections[key] is List && (_selections[key] as List).isEmpty) return false;
    }
    return true;
  }

  void _selectChip(String groupKey, String chipId, bool single) {
    setState(() {
      if (single) {
        _selections[groupKey] = chipId;
      } else {
        final list = (_selections[groupKey] as List<String>?) ?? [];
        if (list.contains(chipId)) { list.remove(chipId); } else { list.add(chipId); }
        _selections[groupKey] = list;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ..._groups.map((g) {
        final key = g['key'] as String;
        final label = g['label'] as String;
        final single = g['single'] as bool? ?? true;
        final chips = g['chips'] as List? ?? [];
        final selectedValue = _selections[key];

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: chips.map((c) {
              final cId = c['id'] as String;
              final cLabel = c['label'] as String;
              final on = single ? selectedValue == cId : (selectedValue is List && selectedValue.contains(cId));

              return GestureDetector(
                onTap: () => _selectChip(key, cId, single),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: on ? _accent : _accentLight,
                    border: Border.all(color: on ? _accent : const Color(0xFFE8E5F0))),
                  child: Text(cLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: on ? Colors.white : const Color(0xFF4A4458)))));
            }).toList()),
          ]));
      }),
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton(
          onPressed: _allFilled ? () => widget.onDone(_selections) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent, disabledBackgroundColor: _accent.withOpacity(0.3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          child: const Text('Devam', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════
// PHOTO CAPTURE — kamera veya galeri
// ═══════════════════════════════════════════════════════════

class FlowPhotoCapture extends StatelessWidget {
  const FlowPhotoCapture({super.key, required this.data, required this.onPhoto, required this.onSkip});
  final Map<String, dynamic> data;
  final void Function(Uint8List bytes) onPhoto;
  final VoidCallback onSkip;

  Future<void> _pick(BuildContext context, ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src, maxWidth: 1920, imageQuality: 85);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    onPhoto(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: () => _pick(context, ImageSource.camera),
        child: Container(
          width: double.infinity, height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_R),
            color: _accentLight, border: Border.all(color: const Color(0xFFE8E5F0), width: 1.5)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.1)),
              child: const Icon(Icons.camera_alt_rounded, color: _accent, size: 24)),
            const SizedBox(height: 8),
            const Text('Fotoğraf Çek', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
            Text(data['hint'] as String? ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]))),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 48,
        child: OutlinedButton.icon(
          onPressed: () => _pick(context, ImageSource.gallery),
          icon: const Icon(Icons.photo_library_rounded, size: 18, color: _accent),
          label: const Text('Galeriden Seç', style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _accent.withOpacity(0.3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
      const SizedBox(height: 8),
      TextButton(
        onPressed: onSkip,
        child: Text('Atla, fotoğrafsız devam et', style: TextStyle(fontSize: 13, color: Colors.grey.shade400))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════
// BUDGET SLIDER — slider + preset butonlar
// ═══════════════════════════════════════════════════════════

class FlowBudgetSlider extends StatefulWidget {
  const FlowBudgetSlider({super.key, required this.data, required this.onDone});
  final Map<String, dynamic> data;
  final void Function(int amount) onDone;
  @override
  State<FlowBudgetSlider> createState() => _FlowBudgetSliderState();
}

class _FlowBudgetSliderState extends State<FlowBudgetSlider> {
  late double _value;
  late double _min;
  late double _max;

  @override
  void initState() {
    super.initState();
    _min = (widget.data['min'] as num? ?? 5000).toDouble();
    _max = (widget.data['max'] as num? ?? 200000).toDouble();
    _value = (widget.data['initial'] as num? ?? 40000).toDouble();
  }

  String _formatTL(double v) {
    if (v >= 1000) return '${(v / 1000).round()}K TL';
    return '${v.round()} TL';
  }

  @override
  Widget build(BuildContext context) {
    final presets = widget.data['presets'] as List? ?? [];
    return Column(children: [
      // Büyük rakam göstergesi
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_R),
          color: _accentLight),
        child: Column(children: [
          Text(_formatTL(_value),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A))),
          const SizedBox(height: 4),
          Text('Toplam bütçe', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ]),
      ),
      const SizedBox(height: 16),

      // Slider
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: _accent,
          inactiveTrackColor: _accent.withOpacity(0.12),
          thumbColor: _accent,
          overlayColor: _accent.withOpacity(0.1),
          trackHeight: 6,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14)),
        child: Slider(
          value: _value, min: _min, max: _max,
          divisions: ((_max - _min) / 5000).round(),
          onChanged: (v) => setState(() => _value = v)),
      ),

      // Min-Max labels
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_formatTL(_min), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            Text(_formatTL(_max), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ])),
      const SizedBox(height: 16),

      // Preset chip'ler
      Wrap(spacing: 8, runSpacing: 8,
        children: presets.map((p) {
          final label = p['label'] as String;
          final pVal = (p['value'] as num).toDouble();
          final on = (_value - pVal).abs() < 2500;
          return GestureDetector(
            onTap: () => setState(() => _value = pVal),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: on ? _accent : _accentLight,
                border: Border.all(color: on ? _accent : const Color(0xFFE8E5F0))),
              child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: on ? Colors.white : const Color(0xFF4A4458)))));
        }).toList()),
      const SizedBox(height: 20),

      // Devam
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton(
          onPressed: () => widget.onDone(_value.round()),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          child: const Text('Devam', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════
// CITY SELECT — şehir seçimi (arama + popüler)
// ═══════════════════════════════════════════════════════════

class FlowCitySelect extends StatefulWidget {
  const FlowCitySelect({super.key, required this.data, required this.onSelect});
  final Map<String, dynamic> data;
  final void Function(String city) onSelect;
  @override
  State<FlowCitySelect> createState() => _FlowCitySelectState();
}

class _FlowCitySelectState extends State<FlowCitySelect> {
  final _ctrl = TextEditingController();
  String? _selected;

  List<String> get _popular => (widget.data['popular'] as List?)?.cast<String>() ?? [];

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Arama kutusu
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _accentLight, border: Border.all(color: const Color(0xFFE8E5F0))),
        child: Row(children: [
          const Padding(padding: EdgeInsets.only(left: 14),
            child: Icon(Icons.search_rounded, size: 20, color: Color(0xFF9B97B0))),
          Expanded(child: TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              hintText: 'Şehir ara...', border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14)),
            style: const TextStyle(fontSize: 14, color: Color(0xFF1A1D2A)),
            onSubmitted: (v) { if (v.trim().isNotEmpty) widget.onSelect(v.trim()); })),
        ])),
      const SizedBox(height: 16),

      // Popüler şehirler
      Text('Popüler şehirler', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8,
        children: _popular.map((city) {
          final on = _selected == city;
          return GestureDetector(
            onTap: () => setState(() => _selected = city),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: on ? _accent : _accentLight,
                border: Border.all(color: on ? _accent : const Color(0xFFE8E5F0))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.location_on_rounded, size: 14,
                  color: on ? Colors.white : const Color(0xFF9B97B0)),
                const SizedBox(width: 6),
                Text(city, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: on ? Colors.white : const Color(0xFF4A4458))),
              ])));
        }).toList()),
      const SizedBox(height: 20),

      // Devam
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton(
          onPressed: _selected != null ? () => widget.onSelect(_selected!) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent, disabledBackgroundColor: _accent.withOpacity(0.3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          child: const Text('Devam', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════
// COLOR MOOD — mood/atmosfer seçimi
// ═══════════════════════════════════════════════════════════

class FlowColorMood extends StatefulWidget {
  const FlowColorMood({super.key, required this.data, required this.onSelect});
  final Map<String, dynamic> data;
  final void Function(String moodId) onSelect;
  @override
  State<FlowColorMood> createState() => _FlowColorMoodState();
}

class _FlowColorMoodState extends State<FlowColorMood> {
  String? _selected;
  List<dynamic> get _moods => widget.data['moods'] as List? ?? [];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ..._moods.map((m) {
        final id = m['id'] as String;
        final label = m['label'] as String;
        final emoji = m['emoji'] as String;
        final colors = (m['colors'] as List?)?.cast<String>() ?? [];
        final on = _selected == id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => setState(() => _selected = id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_R),
                color: on ? _accent.withOpacity(0.06) : _accentLight,
                border: Border.all(color: on ? _accent : const Color(0xFFE8E5F0), width: on ? 2 : 1)),
              child: Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: on ? _accent : const Color(0xFF1A1D2A))),
                  const SizedBox(height: 6),
                  // Renk örnekleri
                  Row(children: colors.map((hex) {
                    final c = Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
                    return Container(width: 22, height: 22, margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: c));
                  }).toList()),
                ])),
                if (on) Container(width: 24, height: 24,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _accent),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 14)),
              ]))));
      }),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton(
          onPressed: _selected != null ? () => widget.onSelect(_selected!) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent, disabledBackgroundColor: _accent.withOpacity(0.3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          child: const Text('Devam', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════
// STYLE HERO — stil detay hero kartı
// ═══════════════════════════════════════════════════════════

class FlowStyleHero extends StatelessWidget {
  const FlowStyleHero({super.key, required this.data, required this.onContinue});
  final Map<String, dynamic> data;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final styleName = data['styleName'] as String? ?? 'Modern';
    // Stil görseli bul
    final styleOpt = kStyleOptions.firstWhere(
      (s) => s.label.toLowerCase() == styleName.toLowerCase() || s.id == styleName.toLowerCase(),
      orElse: () => kStyleOptions.first);

    return Column(children: [
      // Hero görsel
      ClipRRect(
        borderRadius: BorderRadius.circular(_R),
        child: CachedNetworkImage(
          imageUrl: styleOpt.image, height: 200, width: double.infinity, fit: BoxFit.cover,
          placeholder: (_, __) => Container(height: 200, color: _accentLight),
          errorWidget: (_, __, ___) => Container(height: 200, color: _accentLight))),
      const SizedBox(height: 14),
      // Stil adı + kısa açıklama
      Align(alignment: Alignment.centerLeft,
        child: Text(styleOpt.label,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A)))),
      const SizedBox(height: 6),
      Align(alignment: Alignment.centerLeft,
        child: Text(_styleDesc(styleOpt.id),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5))),
      const SizedBox(height: 16),
      // Etiketler
      Wrap(spacing: 8, runSpacing: 8,
        children: _styleTags(styleOpt.id).map((tag) =>
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _accentLight),
            child: Text(tag, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6C5CE7))))).toList()),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton(
          onPressed: onContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          child: const Text('Bu stili uygula', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
    ]);
  }

  static String _styleDesc(String id) {
    const m = {
      'japandi': 'Japon minimalizmi ile İskandinav sıcaklığının buluşması. Doğal malzemeler, düşük mobilyalar ve sakin renkler.',
      'scandinavian': 'Beyaz tonlar, doğal ahşap ve fonksiyonel tasarım. Ferah, aydınlık ve sade yaşam alanları.',
      'modern': 'Temiz çizgiler, nötr renkler ve açık alanlar. Fonksiyonellik ile estetiğin dengesi.',
      'bohemian': 'Renkli tekstiller, doğal dokular ve eklektik detaylar. Özgür ruhlu, kişisel bir ifade.',
      'industrial': 'Açık tuğla, metal ve ahşap. Ham, işlenmemiş yüzeyler ile karakter dolu mekanlar.',
      'rustic': 'Doğal ahşap, taş ve sıcak tonlar. Kır evi sıcaklığında, rahat yaşam alanları.',
      'minimalist': 'Az çoktur. Sadece gerekli olanlar, geniş alanlar ve huzurlu bir atmosfer.',
      'classic': 'Zarif mobilyalar, simetrik düzen ve zengin dokular. Zamansız bir şıklık.',
    };
    return m[id] ?? 'Modern ve şık bir yaşam alanı.';
  }

  static List<String> _styleTags(String id) {
    const m = {
      'japandi': ['#doğal', '#minimal', '#sıcak', '#ahşap'],
      'scandinavian': ['#beyaz', '#fonksiyonel', '#aydınlık', '#hygge'],
      'modern': ['#temiz', '#nötr', '#geometrik', '#açık'],
      'bohemian': ['#renkli', '#tekstil', '#eklektik', '#özgür'],
      'industrial': ['#metal', '#tuğla', '#ham', '#loft'],
      'rustic': ['#ahşap', '#taş', '#sıcak', '#doğal'],
      'minimalist': ['#sade', '#beyaz', '#huzur', '#az'],
      'classic': ['#zarif', '#simetrik', '#zengin', '#zamansız'],
    };
    return m[id] ?? ['#modern', '#şık'];
  }
}

// ═══════════════════════════════════════════════════════════
// PROGRESS BAR
// ═══════════════════════════════════════════════════════════

class FlowProgressBar extends StatelessWidget {
  const FlowProgressBar({super.key, required this.progress, required this.stepLabel});
  final double progress;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        Row(children: [
          Text(stepLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400)),
          const Spacer(),
          Text('${(progress * 100).round()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _accent.withOpacity(0.6))),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress, minHeight: 4,
            backgroundColor: _accent.withOpacity(0.08),
            valueColor: const AlwaysStoppedAnimation(_accent))),
      ]));
  }
}
'''

# ═══════════════════════════════════════════════════════════════
# 3. RESULT WIDGETS — Sonuç kartları (AI response'dan parse)
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "widgets", "flow_result_widgets.dart")] = r'''import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _accent = Color(0xFF6C5CE7);
const _accentLight = Color(0xFFF3F0FF);
const _R = 16.0;

// ═══════════════════════════════════════════════════════════
// COLOR PALETTE CARD
// ═══════════════════════════════════════════════════════════

class ResultColorPalette extends StatelessWidget {
  const ResultColorPalette({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'Renk Paleti';
    final colors = data['colors'] as List? ?? [];
    final tip = data['tip'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        color: _accentLight, border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
        const SizedBox(height: 12),
        // Renk swatchları
        Row(children: colors.map((c) {
          final hex = (c['hex'] as String? ?? '#888888').replaceAll('#', '');
          final name = c['name'] as String? ?? '';
          final usage = c['usage'] as String? ?? '';
          final color = Color(int.parse('FF$hex', radix: 16));
          return Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(children: [
              Container(height: 48, decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10), color: color)),
              const SizedBox(height: 6),
              Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF4A4458)),
                textAlign: TextAlign.center, maxLines: 1),
              if (usage.isNotEmpty) Text(usage,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                textAlign: TextAlign.center, maxLines: 1),
            ])));
        }).toList()),
        if (tip != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
              color: const Color(0xFFEDE9FF)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💡', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(child: Text(tip, style: const TextStyle(fontSize: 12, color: Color(0xFF4A4458), height: 1.4))),
            ])),
        ],
      ]));
  }
}

// ═══════════════════════════════════════════════════════════
// PRODUCT GRID CARD
// ═══════════════════════════════════════════════════════════

class ResultProductGrid extends StatelessWidget {
  const ResultProductGrid({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'Ürün Önerileri';
    final products = data['products'] as List? ?? [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
      const SizedBox(height: 10),
      ...products.map((p) {
        final name = p['name'] as String? ?? '';
        final price = p['price'] as String? ?? '';
        final reason = p['reason'] as String? ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white, border: Border.all(color: const Color(0xFFF0EDF5))),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: _accentLight),
              child: const Icon(Icons.shopping_bag_rounded, size: 20, color: _accent)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
              const SizedBox(height: 2),
              Text(reason, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 2),
            ])),
            Text(price, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _accent)),
          ]));
      }),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════
// BUDGET PLAN CARD
// ═══════════════════════════════════════════════════════════

class ResultBudgetPlan extends StatelessWidget {
  const ResultBudgetPlan({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final total = data['total_budget'] as String? ?? '';
    final items = data['items'] as List? ?? [];
    final tip = data['tip'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('💰', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          const Text('Bütçe Planı', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99),
              color: Colors.white.withOpacity(0.2)),
            child: Text(total, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
        const SizedBox(height: 14),
        ...items.map((item) {
          final cat = item['category'] as String? ?? '';
          final amount = item['amount'] as String? ?? '';
          final priority = item['priority'] as String? ?? 'medium';
          final note = item['note'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: priority == 'high' ? const Color(0xFFEF4444) :
                    priority == 'medium' ? const Color(0xFFFBBF24) : Colors.white.withOpacity(0.4))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cat, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                if (note.isNotEmpty) Text(note,
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6)), maxLines: 1),
              ])),
              Text(amount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.9))),
            ]));
        }),
        if (tip != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
              color: Colors.white.withOpacity(0.12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💡', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(child: Text(tip,
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85), height: 1.4))),
            ])),
        ],
      ]));
  }
}

// ═══════════════════════════════════════════════════════════
// DESIGNER CARD
// ═══════════════════════════════════════════════════════════

class ResultDesignerCard extends StatelessWidget {
  const ResultDesignerCard({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final designers = data['designers'] as List? ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Sana Uygun Tasarımcılar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
      const SizedBox(height: 10),
      ...designers.map((d) {
        final name = d['name'] as String? ?? '';
        final title = d['title'] as String? ?? '';
        final rating = (d['rating'] as num?)?.toDouble() ?? 4.5;
        final minBudget = d['min_budget'] as String? ?? '';
        final bio = d['bio'] as String? ?? '';
        final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_R),
            color: Colors.white, border: Border.all(color: const Color(0xFFF0EDF5))),
          child: Column(children: [
            Row(children: [
              // Avatar
              Container(width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
                child: Center(child: Text(initials,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
                Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
              // Rating
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: const Color(0xFFFFF7ED)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 3),
                  Text(rating.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B))),
                ])),
            ]),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(bio, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4), maxLines: 2),
            ],
            const SizedBox(height: 10),
            Row(children: [
              if (minBudget.isNotEmpty) Text('Min: $minBudget',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400)),
              const Spacer(),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://www.evlumba.com/tasarimcilar'), mode: LaunchMode.externalApplication),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _accent),
                  child: const Text('İletişime Geç', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)))),
            ]),
          ]));
      }),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════
// QUICK TIPS CARD
// ═══════════════════════════════════════════════════════════

class ResultQuickTips extends StatelessWidget {
  const ResultQuickTips({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final tips = data['tips'] as List? ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        color: _accentLight, border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💡 Pratik İpuçları', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
        const SizedBox(height: 10),
        ...tips.map((tip) {
          final t = tip is String ? tip : (tip as Map<String, dynamic>?)?['text'] ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.5))),
              const SizedBox(width: 10),
              Expanded(child: Text(t.toString(),
                style: const TextStyle(fontSize: 13, color: Color(0xFF4A4458), height: 1.5))),
            ]));
        }),
      ]));
  }
}

// ═══════════════════════════════════════════════════════════
// LOADING SHIMMER — AI sonuç bekleme
// ═══════════════════════════════════════════════════════════

class ResultLoadingShimmer extends StatefulWidget {
  const ResultLoadingShimmer({super.key});
  @override
  State<ResultLoadingShimmer> createState() => _ResultLoadingShimmerState();
}

class _ResultLoadingShimmerState extends State<ResultLoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  static const _messages = [
    '🎨 Stilini analiz ediyorum...',
    '🏠 Odanı hayal ediyorum...',
    '💡 Öneriler hazırlıyorum...',
    '✨ Son dokunuşlar...',
  ];
  int _msgIdx = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() => _msgIdx = (_msgIdx + 1) % _messages.length);
          _ctrl.forward(from: 0);
        }
      })
      ..forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 20),
      // Animated koala icon
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        builder: (_, v, child) => Opacity(opacity: v, child: Transform.scale(scale: 0.8 + 0.2 * v, child: child)),
        child: Container(width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
          child: const Center(child: Text('🐨', style: TextStyle(fontSize: 28))))),
      const SizedBox(height: 16),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(_messages[_msgIdx],
          key: ValueKey(_msgIdx),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6C5CE7)))),
      const SizedBox(height: 24),
      // Shimmer kartlar
      ...List.generate(3, (i) => _shimmerCard(i)),
    ]);
  }

  Widget _shimmerCard(int idx) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final delay = idx * 0.15;
        final opacity = ((_ctrl.value - delay) * 3).clamp(0.3, 0.7);
        return Opacity(opacity: opacity,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            height: idx == 0 ? 80 : 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _accentLight)));
      });
  }
}
'''

# ═══════════════════════════════════════════════════════════════
# 4. GUIDED FLOW SCREEN — Orkestratör ekranı
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "views", "guided_flow_screen.dart")] = r'''import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/flow_models.dart';
import '../services/koala_ai_service.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/flow_result_widgets.dart';

class GuidedFlowScreen extends StatefulWidget {
  const GuidedFlowScreen({super.key, required this.flow});
  final FlowState flow;

  @override
  State<GuidedFlowScreen> createState() => _GuidedFlowScreenState();
}

class _GuidedFlowScreenState extends State<GuidedFlowScreen>
    with SingleTickerProviderStateMixin {
  late FlowState _flow;
  final _ai = KoalaAIService();
  final _scrollCtrl = ScrollController();

  // Result state
  bool _loading = false;
  KoalaResponse? _result;
  String? _error;

  // Animations
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _flow = widget.flow;
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() { _fadeCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  // ── Step ilerleme ──
  void _advance(String stepId, dynamic value) {
    _flow.collected[stepId] = value;
    setState(() {
      _flow.currentStep++;
      // Eğer result step'e geldiyse AI'ı çağır
      if (_flow.current?.widgetType == 'result') {
        _fetchResult();
      }
    });
    _animateIn();
    _scrollToTop();
  }

  void _animateIn() {
    _fadeCtrl.reset();
    _fadeCtrl.forward();
  }

  void _scrollToTop() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ── AI çağrısı ──
  Future<void> _fetchResult() async {
    setState(() { _loading = true; _error = null; });

    try {
      final params = <String, String>{};
      // Collected data'yı params'a dönüştür
      _flow.collected.forEach((key, value) {
        if (value is String) {
          params[key] = value;
        } else if (value is List) {
          params[key] = value.join(', ');
        } else if (value is int || value is double) {
          params[key] = value.toString();
        } else if (value is Map) {
          value.forEach((k, v) {
            if (v is String) params[k.toString()] = v;
            else if (v is List) params[k.toString()] = v.join(', ');
          });
        }
      });

      // Flow type'a göre intent belirle
      KoalaIntent intent;
      switch (_flow.type) {
        case FlowType.roomRenovation:
          intent = KoalaIntent.roomRenovation;
          params['room'] = params['room_select'] ?? 'salon';
          params['style'] = params['style_pick'] ?? 'modern';
          params['budget'] = params['budget'] ?? '30-60K TL';
          params['priority'] = params['priority'] ?? 'komple';
          break;
        case FlowType.budgetPlan:
          intent = KoalaIntent.budgetPlan;
          params['room'] = params['room_select'] ?? 'salon';
          break;
        case FlowType.designerMatch:
          intent = KoalaIntent.designerMatch;
          params['style'] = params['style_pick'] ?? 'modern';
          break;
        case FlowType.styleExplore:
          intent = KoalaIntent.styleExplore;
          params['style'] = _flow.initialParam ?? 'Modern';
          break;
        case FlowType.colorAdvice:
          intent = KoalaIntent.colorAdvice;
          params['room'] = params['room_select'] ?? 'salon';
          break;
        case FlowType.freeChat:
          intent = KoalaIntent.freeChat;
          break;
      }

      // Fotoğraf var mı?
      Uint8List? photo;
      if (_flow.collected.containsKey('photo') && _flow.collected['photo'] is Uint8List) {
        photo = _flow.collected['photo'] as Uint8List;
      }

      final response = await _ai.askWithIntent(
        intent: intent,
        params: params,
        photo: photo,
      );

      if (mounted) setState(() { _result = response; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _flow.current;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          // ── Top bar ──
          _buildTopBar(),

          // ── Progress ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: FlowProgressBar(
              progress: _flow.progress,
              stepLabel: step != null
                ? 'Adım ${_flow.currentStep + 1}/${_flow.steps.length}'
                : 'Tamamlandı')),

          // ── Content ──
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Koala mesajı
                    if (step != null) _buildKoalaMessage(step.koalaMessage),
                    const SizedBox(height: 16),

                    // Widget
                    if (step != null) _buildStepWidget(step),
                  ])))),
        ])),
    );
  }

  // ── Top bar ──
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          onPressed: () {
            if (_flow.currentStep > 0 && !_loading) {
              setState(() { _flow.currentStep--; _result = null; });
              _animateIn();
            } else {
              Navigator.of(context).pop();
            }
          }),
        const Spacer(),
        // Flow title
        Text(_flowTitle(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
        const Spacer(),
        const SizedBox(width: 48), // balance
      ]));
  }

  String _flowTitle() {
    switch (_flow.type) {
      case FlowType.roomRenovation: return 'Odanı Tara';
      case FlowType.budgetPlan: return 'Bütçe Planla';
      case FlowType.designerMatch: return 'Tasarımcı Bul';
      case FlowType.styleExplore: return 'Stil Keşfet';
      case FlowType.colorAdvice: return 'Renk Öner';
      case FlowType.freeChat: return 'Koala';
    }
  }

  // ── Koala mesajı ──
  Widget _buildKoalaMessage(String text) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 32, height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
        child: const Center(child: Text('🐨', style: TextStyle(fontSize: 16)))),
      const SizedBox(width: 10),
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            color: const Color(0xFFF3F0FF)),
          child: Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1D2A), height: 1.5)))),
    ]);
  }

  // ── Step widget ──
  Widget _buildStepWidget(FlowStep step) {
    switch (step.widgetType) {
      case 'room_select':
        return FlowRoomSelect(onSelect: (id) => _advance(step.id, id));

      case 'image_grid':
        return FlowImageGrid(
          data: step.widgetData,
          onDone: (ids) => _advance(step.id, ids));

      case 'chip_select':
        return FlowChipSelect(
          data: step.widgetData,
          onDone: (selections) => _advance(step.id, selections));

      case 'photo_capture':
        return FlowPhotoCapture(
          data: step.widgetData,
          onPhoto: (bytes) => _advance('photo', bytes),
          onSkip: () => _advance(step.id, 'skipped'));

      case 'budget_slider':
        return FlowBudgetSlider(
          data: step.widgetData,
          onDone: (amount) => _advance(step.id, amount));

      case 'city_select':
        return FlowCitySelect(
          data: step.widgetData,
          onSelect: (city) => _advance(step.id, city));

      case 'color_mood':
        return FlowColorMood(
          data: step.widgetData,
          onSelect: (mood) => _advance(step.id, mood));

      case 'style_hero':
        return FlowStyleHero(
          data: step.widgetData,
          onContinue: () => _advance(step.id, step.widgetData['styleName']));

      case 'result':
        return _buildResultSection();

      default:
        return Text('Bilinmeyen widget: ${step.widgetType}');
    }
  }

  // ── Result section ──
  Widget _buildResultSection() {
    if (_loading) return const ResultLoadingShimmer();

    if (_error != null) {
      return Column(children: [
        const SizedBox(height: 20),
        const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFEF4444)),
        const SizedBox(height: 12),
        Text('Bir sorun oluştu', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _fetchResult,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C5CE7), foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('Tekrar Dene')),
      ]);
    }

    if (_result == null) return const SizedBox();

    // Parse AI cards and build result widgets
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._result!.cards.map((card) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _buildResultCard(card))),

        // Sohbete devam butonu
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, height: 48,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF6C5CE7)),
            label: const Text('Sohbete devam et',
              style: TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: const Color(0xFF6C5CE7).withOpacity(0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
      ]);
  }

  Widget _buildResultCard(KoalaCard card) {
    switch (card.type) {
      case 'color_palette':
        return ResultColorPalette(data: card.data);
      case 'product_grid':
        return ResultProductGrid(data: card.data);
      case 'budget_plan':
        return ResultBudgetPlan(data: card.data);
      case 'designer_card':
        return ResultDesignerCard(data: card.data);
      case 'quick_tips':
        return ResultQuickTips(data: card.data);
      case 'style_analysis':
        // Style analysis → color palette + tags olarak göster
        final colors = card.data['color_palette'] as List? ?? [];
        return ResultColorPalette(data: {
          'title': card.data['style_name'] ?? 'Stil Analizi',
          'colors': colors,
          'tip': card.data['description'],
        });
      default:
        // Bilinmeyen kart tipi → text olarak göster
        final text = card.data['text'] as String? ?? jsonEncode(card.data);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFFF3F0FF)),
          child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF4A4458), height: 1.5)));
    }
  }
}
'''

# ═══════════════════════════════════════════════════════════════
# 5. HOME SCREEN — Kartlar artık GuidedFlowScreen'e yönleniyor
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "views", "home_screen.dart")] = r'''import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/flow_models.dart';
import '../stores/scan_store.dart';
import 'chat_detail_screen.dart';
import 'guided_flow_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _inputCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late final AnimationController _chipFade;
  Timer? _chipTimer;
  int _chipIdx = 0;
  Uint8List? _pendingPhoto;

  static const _chips = [
    ['\u{1F3E0}', 'odamı yeniden tasarla'],
    ['\u{1F3A8}', 'duvar rengi öner'],
    ['\u{1F6CB}\u{FE0F}', 'bu dolaba ne yakışır?'],
    ['\u{1F4A1}', 'bütçeye uygun dekorasyon'],
  ];

  @override
  void initState() {
    super.initState();
    _chipFade = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..value = 1.0;
    _chipTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _chipFade.reverse().then((_) {
        if (!mounted) return;
        setState(() => _chipIdx = (_chipIdx + 1) % _chips.length);
        _chipFade.forward();
      });
    });
  }

  @override
  void dispose() { _inputCtrl.dispose(); _chipFade.dispose(); _chipTimer?.cancel(); super.dispose(); }

  // ── Navigasyon helpers ──
  void _submit() {
    final t = _inputCtrl.text.trim();
    if (t.isEmpty && _pendingPhoto == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatDetailScreen(
      initialText: t.isNotEmpty ? t : null, initialPhoto: _pendingPhoto)));
    _inputCtrl.clear();
    setState(() => _pendingPhoto = null);
  }

  void _go(String text) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatDetailScreen(initialText: text)));

  void _startFlow(FlowState flow) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuidedFlowScreen(flow: flow)));

  void _showPicker() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.grey.shade300)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _PickBtn(Icons.camera_alt_rounded, 'Kamera', () { Navigator.pop(context); _doPick(ImageSource.camera); })),
            const SizedBox(width: 12),
            Expanded(child: _PickBtn(Icons.photo_library_rounded, 'Galeri', () { Navigator.pop(context); _doPick(ImageSource.gallery); })),
          ]),
        ])));
  }

  Future<void> _doPick(ImageSource src) async {
    final f = await _picker.pickImage(source: src, maxWidth: 1920, imageQuality: 85);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    // Fotoğraf alındı → direkt room renovation flow başlat
    _startFlow(FlowBuilder.buildRoomRenovation());
  }

  @override
  Widget build(BuildContext context) {
    final btm = MediaQuery.of(context).padding.bottom;
    final user = FirebaseAuth.instance.currentUser;
    final inputH = _pendingPhoto != null ? 114.0 : 58.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        Positioned.fill(
          bottom: inputH + btm,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Top bar ──
              SliverToBoxAdapter(child: SafeArea(bottom: false, child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(children: [
                  const Spacer(),
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF3F0FF)),
                    child: Stack(children: [
                      const Center(child: Icon(Icons.notifications_none_rounded, size: 20, color: Color(0xFF6C5CE7))),
                      Positioned(top: 6, right: 6, child: Container(width: 8, height: 8,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFEF4444),
                          border: Border.all(color: Colors.white, width: 1.5)))),
                    ])),
                  const SizedBox(width: 8),
                  _avatar(user),
                ])))),

              // ── Hero ──
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 4),
                child: Column(children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0xFFF0ECFF)),
                    child: const Icon(Icons.auto_awesome, size: 22, color: Color(0xFF6C5CE7))),
                  const SizedBox(height: 8),
                  const Text('koala', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -0.6)),
                  const SizedBox(height: 2),
                  Text('tara. keşfet. tasarla.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, letterSpacing: 0.2)),
                  const SizedBox(height: 14),
                  FadeTransition(opacity: _chipFade, child: GestureDetector(
                    onTap: () => _go(_chips[_chipIdx][1]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFF3F0FF)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_chips[_chipIdx][0], style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 7),
                        Text(_chips[_chipIdx][1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4A4458))),
                      ])))),
                ]))),

              // ═══════════════════════════════════════════════
              // SECTION 1: Hızlı Başla (guided flow'lara yönlendir)
              // ═══════════════════════════════════════════════
              SliverToBoxAdapter(child: _section('Hızlı Başla')),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(children: [
                  // Full-width hero CTA → Room Renovation Flow
                  _FullCTA(
                    icon: Icons.camera_alt_rounded,
                    title: 'Odanı tara, stilini öğren',
                    desc: 'Fotoğraf çek → AI analiz etsin → öneriler alsın',
                    onTap: () => _startFlow(FlowBuilder.buildRoomRenovation()),
                  ),
                  const SizedBox(height: 8),
                  // Two small CTAs → Budget & Designer Flows
                  Row(children: [
                    Expanded(child: _MiniCTA(
                      emoji: '\u{1F4B0}',
                      title: 'Bütçe Planla',
                      onTap: () => _startFlow(FlowBuilder.buildBudgetPlan()),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniCTA(
                      emoji: '\u{1F464}',
                      title: 'Tasarımcı Bul',
                      onTap: () => _startFlow(FlowBuilder.buildDesignerMatch()),
                    )),
                  ]),
                ]))),

              // ═══════════════════════════════════════════════
              // SECTION 2: İlham Al → Style Explore Flows
              // ═══════════════════════════════════════════════
              SliverToBoxAdapter(child: _section('İlham Al')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverToBoxAdapter(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _InspoCard(
                        url: 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=400&q=80',
                        label: 'Japandi Salon', h: 190,
                        onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Japandi')),
                      ),
                      _InspoCard(
                        url: 'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?auto=format&fit=crop&w=400&q=80',
                        label: 'Modern Mutfak', h: 150,
                        onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Modern')),
                      ),
                    ])),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _InspoCard(
                        url: 'https://images.unsplash.com/photo-1505691938895-1758d7feb511?auto=format&fit=crop&w=400&q=80',
                        label: 'Skandinav Oturma', h: 160,
                        onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Skandinav')),
                      ),
                      _InspoCard(
                        url: 'https://images.unsplash.com/photo-1540518614846-7eded433c457?auto=format&fit=crop&w=400&q=80',
                        label: 'Bohem Yatak Odası', h: 180,
                        onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Bohem')),
                      ),
                    ])),
                  ]),
                ),
              ),

              // ═══════════════════════════════════════════════
              // SECTION 3: Keşfet (trend + poll → Color Advice Flow)
              // ═══════════════════════════════════════════════
              SliverToBoxAdapter(child: _section('Keşfet')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverToBoxAdapter(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _TrendCard(onTap: () => _startFlow(FlowBuilder.buildColorAdvice())),
                      _FactCard('\u{1F33F}', 'Bitkiler odadaki\nstresi %37 azaltıyor'),
                    ])),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _PollCard(onSelect: (s) => _startFlow(FlowBuilder.buildStyleExplore(s))),
                      _FactCard('\u{2728}', 'Açık renkli perdeler\nodayı %30 geniş gösterir'),
                    ])),
                  ]),
                ),
              ),

              // ═══════════════════════════════════════════════
              // SECTION 4: Daha Fazla İlham
              // ═══════════════════════════════════════════════
              SliverToBoxAdapter(child: _section('Daha Fazla')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverToBoxAdapter(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _InspoCard(
                        url: 'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=400&q=80',
                        label: 'Minimalist Banyo', h: 160,
                        onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Minimalist')),
                      ),
                      _InspoCard(
                        url: 'https://images.unsplash.com/photo-1556909172-54557c7e4fb7?auto=format&fit=crop&w=400&q=80',
                        label: 'Rustik Mutfak', h: 170,
                        onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Rustik')),
                      ),
                    ])),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _InspoCard(
                        url: 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=400&q=80',
                        label: 'Yaz Balkonu', h: 180,
                        onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Minimalist')),
                      ),
                      _InspoCard(
                        url: 'https://images.unsplash.com/photo-1618221195710-dd6b41faaea6?auto=format&fit=crop&w=400&q=80',
                        label: 'Lüks Oturma', h: 150,
                        onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Klasik')),
                      ),
                    ])),
                  ]),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),

        // ── Input bar ──
        Positioned(left: 0, right: 0, bottom: 0, child: _buildInput(btm)),
      ]),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 22, 14, 10),
    child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
  );

  Widget _buildInput(double btm) {
    final has = _inputCtrl.text.isNotEmpty || _pendingPhoto != null;
    return Container(
      decoration: BoxDecoration(color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -2))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_pendingPhoto != null) Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0xFFF5F3FA)),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Image.memory(_pendingPhoto!, width: 40, height: 40, fit: BoxFit.cover)),
            const SizedBox(width: 10),
            Expanded(child: Text('Fotoğraf hazır – metin ekle veya gönder',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500))),
            GestureDetector(onTap: () => setState(() => _pendingPhoto = null),
              child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400)),
          ])),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, btm + 8),
          child: Container(height: 46,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFF3F1FA)),
            child: Row(children: [
              GestureDetector(onTap: _showPicker, child: Padding(padding: const EdgeInsets.only(left: 5),
                child: Container(width: 34, height: 34,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.7)),
                  child: Icon(Icons.add_rounded, size: 20, color: Colors.grey.shade600)))),
              Expanded(child: TextField(controller: _inputCtrl,
                decoration: InputDecoration(
                  hintText: _pendingPhoto != null ? 'Ne sormak istersin?' : 'Koala\u{2019}ya sor...',
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400), border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1D2A)),
                onSubmitted: (_) => _submit(), onChanged: (_) => setState(() {}))),
              GestureDetector(onTap: has ? _submit : null, child: Padding(padding: const EdgeInsets.only(right: 5),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 34, height: 34,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: has ? const Color(0xFF6C5CE7) : Colors.transparent),
                  child: Icon(Icons.arrow_upward_rounded, size: 18,
                    color: has ? Colors.white : Colors.grey.shade400)))),
            ]))),
      ]),
    );
  }

  Widget _avatar(User? user) {
    final url = user?.photoURL;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
      child: Container(width: 36, height: 36,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFEDEAF5)),
        child: url != null
            ? ClipOval(child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person, size: 16, color: Colors.grey.shade400)))
            : Icon(Icons.person, size: 16, color: Colors.grey.shade400)),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CARD WIDGETS (değişmedi)
// ═══════════════════════════════════════════════════════════

const _R = 18.0;

class _FullCTA extends StatelessWidget {
  const _FullCTA({required this.icon, required this.title, required this.desc, required this.onTap});
  final IconData icon; final String title, desc; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), color: Colors.white.withOpacity(0.18)),
          child: Icon(icon, size: 22, color: Colors.white)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 3),
          Text(desc, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75), height: 1.3)),
        ])),
        Icon(Icons.arrow_forward_rounded, color: Colors.white.withOpacity(0.5)),
      ]))));
}

class _MiniCTA extends StatelessWidget {
  const _MiniCTA({required this.emoji, required this.title, required this.onTap});
  final String emoji, title; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        color: const Color(0xFFF8F6FF), border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A4458))),
      ])));
}

class _InspoCard extends StatelessWidget {
  const _InspoCard({required this.url, required this.label, required this.h, required this.onTap});
  final String url, label; final double h; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(onTap: onTap,
    child: Container(height: h, decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: const Color(0xFFF3F1F8)),
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(borderRadius: BorderRadius.circular(_R),
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: const Color(0xFFF3F1F8)),
            errorWidget: (_, __, ___) => Container(color: const Color(0xFFF3F1F8)))),
        Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.55)], stops: const [0.45, 1]))),
        Positioned(bottom: 12, left: 12, child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
      ]))));
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: const Color(0xFFFAF8FF),
        border: Border.all(color: const Color(0xFFF0EDF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('\u{1F3A8}  2026 Trend', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF6C5CE7).withOpacity(0.6))),
        const SizedBox(height: 10),
        Row(children: [_sw(const Color(0xFFC4704A)), const SizedBox(width: 5), _sw(const Color(0xFF8B9E6B)), const SizedBox(width: 5), _sw(const Color(0xFFE8D5C4))]),
        const SizedBox(height: 8),
        Text('Odana uygula \u{2192}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF6C5CE7).withOpacity(0.7))),
      ]))));
  Widget _sw(Color c) => Expanded(child: Container(height: 24, decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: c)));
}

class _FactCard extends StatelessWidget {
  const _FactCard(this.emoji, this.fact);
  final String emoji, fact;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
      color: const Color(0xFFFAF8FF), border: Border.all(color: const Color(0xFFF0EDF5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text(emoji, style: const TextStyle(fontSize: 15)), const SizedBox(width: 6),
        Text('Biliyor muydun?', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade400))]),
      const SizedBox(height: 8),
      Text(fact, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A), height: 1.4)),
    ])));
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.onSelect});
  final void Function(String) onSelect;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: const Color(0xFFF8F6FF)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('\u{1F3AF}  Senin tarzın?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: ['Minimalist', 'Bohem', 'Japandi', 'Modern'].map((o) =>
        GestureDetector(onTap: () => onSelect(o),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFEDE9FF)),
            child: Text(o, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6C5CE7)))))).toList()),
    ])));
}

class _PickBtn extends StatelessWidget {
  const _PickBtn(this.icon, this.label, this.onTap);
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0xFFF5F2FF)),
      child: Column(children: [Icon(icon, size: 28, color: const Color(0xFF6C5CE7)), const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A4458)))])));
}
'''

# ═══════════════════════════════════════════════════════════════
# Write all files
# ═══════════════════════════════════════════════════════════════
print("=" * 60)
print("KOALA GUIDED FLOW SYSTEM — File Generator")
print("=" * 60)

for rel_path, content in files.items():
    full_path = os.path.join(BASE, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  ✅ {rel_path}")

print()
print("=" * 60)
print(f"  {len(files)} dosya başarıyla oluşturuldu!")
print("=" * 60)
print()
print("Değişen dosyalar:")
print("  📝 lib/models/flow_models.dart        — Tüm flow builder'lar")
print("  📝 lib/widgets/flow_widgets.dart       — 4 yeni widget eklendi")
print("  🆕 lib/widgets/flow_result_widgets.dart — Sonuç kartları")
print("  🆕 lib/views/guided_flow_screen.dart   — Flow orkestratör")
print("  📝 lib/views/home_screen.dart          — Kartlar flow'lara bağlandı")
print()
print("Test etmek için:")
print("  flutter run -d chrome")
