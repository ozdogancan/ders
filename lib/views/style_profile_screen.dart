import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';

class StyleProfileScreen extends StatefulWidget {
  const StyleProfileScreen({super.key});
  @override
  State<StyleProfileScreen> createState() => _StyleProfileScreenState();
}

class _StyleProfileScreenState extends State<StyleProfileScreen> {
  String? _selectedStyle;
  final Set<String> _selectedColors = {};
  String? _selectedRoom;
  String? _selectedBudget;
  int _step = 0;
  bool _saved = false;

  static const _styles = [
    {'name': 'Minimalist', 'emoji': '⬜', 'color': Color(0xFFF1F5F9)},
    {'name': 'Modern', 'emoji': '🔲', 'color': Color(0xFFEDE9FE)},
    {'name': 'Japandi', 'emoji': '🎋', 'color': Color(0xFFF0FDF4)},
    {'name': 'Bohem', 'emoji': '🌿', 'color': Color(0xFFFEF3C7)},
    {'name': 'Skandinav', 'emoji': '❄️', 'color': Color(0xFFEFF6FF)},
    {'name': 'Endüstriyel', 'emoji': '⚙️', 'color': Color(0xFFF1F5F9)},
  ];

  static const _colors = [
    {'name': 'Beyaz', 'hex': '#FFFFFF'},
    {'name': 'Bej', 'hex': '#F5F0E8'},
    {'name': 'Gri', 'hex': '#9CA3AF'},
    {'name': 'Mavi', 'hex': '#3B82F6'},
    {'name': 'Yeşil', 'hex': '#10B981'},
    {'name': 'Terracotta', 'hex': '#C4704A'},
    {'name': 'Lacivert', 'hex': '#1E3A5F'},
    {'name': 'Pembe', 'hex': '#EC4899'},
  ];

  static const _rooms = ['Salon', 'Yatak Odası', 'Mutfak', 'Banyo', 'Çocuk Odası', 'Ofis'];
  static const _budgets = ['💚 10-30K TL', '💛 30-60K TL', '🔥 60-100K TL', '💎 100K+'];

  Future<void> _save() async {
    // Local kayıt (offline fallback)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('koala_style_profile', jsonEncode({
      'primary_style': _selectedStyle,
      'preferred_colors': _selectedColors.toList(),
      'preferred_room': _selectedRoom,
      'budget_band': _selectedBudget,
    }));

    // Supabase'e sync
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && Env.hasSupabaseConfig) {
      try {
        await Supabase.instance.client.from('users').update({
          'style_preference': _selectedStyle,
          'color_preferences': _selectedColors.toList(),
          'preferred_room': _selectedRoom,
          'budget_range': _selectedBudget,
        }).eq('id', uid);
      } catch (_) {}
    }

    setState(() => _saved = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close_rounded, color: Color(0xFF1A1D2A)),
          onPressed: () => Navigator.pop(context)),
        title: const Text('Stil Profilim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
      ),
      body: Column(children: [
        // Progress
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: List.generate(4, (i) => Expanded(
            child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2),
                color: i <= _step ? const Color(0xFF6C5CE7) : const Color(0xFFE5E7EB))))))),
        
        Expanded(child: Padding(padding: const EdgeInsets.all(24),
          child: _buildStep())),
        
        // Navigation buttons
        Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          child: Row(children: [
            if (_step > 0)
              Padding(padding: const EdgeInsets.only(right: 12),
                child: SizedBox(height: 52, width: 52,
                  child: OutlinedButton(
                    onPressed: () { HapticFeedback.lightImpact(); setState(() => _step--); },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: EdgeInsets.zero),
                    child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF6C5CE7))))),
            Expanded(child: SizedBox(height: 52,
              child: ElevatedButton(
                onPressed: _canProceed() ? () {
                  HapticFeedback.lightImpact();
                  if (_step < 3) { setState(() => _step++); }
                  else { _save(); }
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7), foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0),
                child: Text(_step < 3 ? 'Devam' : (_saved ? 'Kaydedildi!' : 'Kaydet'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))))),
          ])),
      ]));
  }

  bool _canProceed() {
    switch (_step) {
      case 0: return _selectedStyle != null;
      case 1: return _selectedColors.isNotEmpty;
      case 2: return _selectedRoom != null;
      case 3: return _selectedBudget != null;
      default: return false;
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _stepStyle();
      case 1: return _stepColors();
      case 2: return _stepRoom();
      case 3: return _stepBudget();
      default: return const SizedBox();
    }
  }

  Widget _stepStyle() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Hangi tarz seni yansıtıyor?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A))),
    const SizedBox(height: 6),
    Text('Birini seç', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
    const SizedBox(height: 24),
    Expanded(child: GridView.count(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.2,
      children: _styles.map((s) {
        final selected = _selectedStyle == s['name'];
        return GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); setState(() => _selectedStyle = s['name'] as String); },
          child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
              color: s['color'] as Color,
              border: Border.all(color: selected ? const Color(0xFF6C5CE7) : Colors.transparent, width: 2)),
            child: Center(child: Text('${s['emoji']}  ${s['name']}',
              style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? const Color(0xFF6C5CE7) : const Color(0xFF4A4458))))));
      }).toList())),
  ]);

  Widget _stepColors() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Hangi renkler hoşuna gider?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A))),
    const SizedBox(height: 6),
    Text('Birden fazla seçebilirsin', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
    const SizedBox(height: 24),
    Expanded(child: GridView.count(crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10,
      children: _colors.map((c) {
        final selected = _selectedColors.contains(c['name']);
        final color = Color(int.parse('FF${(c['hex'] as String).replaceAll('#', '')}', radix: 16));
        return GestureDetector(
          onTap: () { HapticFeedback.lightImpact();
            setState(() { if (selected) {
              _selectedColors.remove(c['name']);
            } else {
              _selectedColors.add(c['name'] as String);
            } }); },
          child: Column(children: [
            AnimatedContainer(duration: const Duration(milliseconds: 200),
              width: 56, height: 56,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: color,
                border: Border.all(color: selected ? const Color(0xFF6C5CE7) : const Color(0xFFE5E7EB), width: selected ? 3 : 1)),
              child: selected ? const Icon(Icons.check_rounded, color: Color(0xFF6C5CE7), size: 22) : null),
            const SizedBox(height: 4),
            Text(c['name'] as String, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          ]));
      }).toList())),
  ]);

  Widget _stepRoom() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Öncelikli odan hangisi?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A))),
    const SizedBox(height: 6),
    Text('Hangi odanı tasarlamak istiyorsun?', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
    const SizedBox(height: 24),
    Expanded(child: ListView(children: _rooms.map((r) {
      final selected = _selectedRoom == r;
      return GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); setState(() => _selectedRoom = r); },
        child: AnimatedContainer(duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
            color: selected ? const Color(0xFFF3F0FF) : const Color(0xFFFAFAFA),
            border: Border.all(color: selected ? const Color(0xFF6C5CE7) : Colors.transparent, width: 2)),
          child: Text(r, style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFF6C5CE7) : const Color(0xFF4A4458)))));
    }).toList())),
  ]);

  Widget _stepBudget() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Bütçen ne kadar?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A))),
    const SizedBox(height: 6),
    Text('Yaklaşık bir aralık seç', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
    const SizedBox(height: 24),
    Expanded(child: ListView(children: _budgets.map((b) {
      final selected = _selectedBudget == b;
      return GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); setState(() => _selectedBudget = b); },
        child: AnimatedContainer(duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
            color: selected ? const Color(0xFFF3F0FF) : const Color(0xFFFAFAFA),
            border: Border.all(color: selected ? const Color(0xFF6C5CE7) : Colors.transparent, width: 2)),
          child: Text(b, style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFF6C5CE7) : const Color(0xFF4A4458)))));
    }).toList())),
  ]);
}
