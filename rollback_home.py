#!/usr/bin/env python3
"""Rollback home_screen.dart to pre-v2 version (from create_guided_flows.py)"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"

path = os.path.join(BASE, "lib", "views", "home_screen.dart")

content = r'''import 'dart:async';
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
// CARD WIDGETS
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

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print(f"✅ home_screen.dart rolled back to pre-v2 version")
print("Run: flutter run -d chrome")
