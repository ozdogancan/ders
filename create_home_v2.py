#!/usr/bin/env python3
"""
Koala Home Screen v2 — 2026 Design Iteration
=============================================
- Glassmorphism / frosted glass kartlar
- Bento grid layout (asimetrik, Pinterest-like)
- Soft depth: subtle shadows, layered cards
- Kinetic typography: animated gradient text
- Micro-interactions: scale on press, staggered entry
- Warm premium palette: cream + soft purple + terracotta
- Greeting based on time of day
- Floating Koala mascot with breathing animation
"""

import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"

files = {}

# ═══════════════════════════════════════════════════════════════
# HOME SCREEN v2 — 2026 Design
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "views", "home_screen.dart")] = r'''import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/flow_models.dart';
import 'chat_detail_screen.dart';
import 'guided_flow_screen.dart';
import 'profile_screen.dart';

// ═══════════════════════════════════════════════════════════
// 2026 DESIGN TOKENS
// ═══════════════════════════════════════════════════════════
class _Tok {
  _Tok._();
  // Warm premium palette
  static const bg = Color(0xFFFAF8F5);           // warm cream
  static const surface = Color(0xFFFFFFFF);
  static const surfaceGlass = Color(0xCCFFFFFF);  // 80% white
  static const accent = Color(0xFF6C5CE7);
  static const accentSoft = Color(0xFFF0ECFF);
  static const accentGlow = Color(0xFF8B7BF7);
  static const terracotta = Color(0xFFD4845A);
  static const sage = Color(0xFF8B9E6B);
  static const ink = Color(0xFF1A1A2E);
  static const inkSoft = Color(0xFF4A4458);
  static const muted = Color(0xFF9B97B0);
  static const border = Color(0x14000000);        // 8% black
  static const shadow = Color(0x0A000000);        // 4% black

  static const r = 22.0;       // card radius
  static const rPill = 999.0;  // pill radius
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _inputCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  Uint8List? _pendingPhoto;

  // Animations
  late AnimationController _breatheCtrl;   // Koala mascot breathing
  late AnimationController _staggerCtrl;   // Staggered card entry
  late AnimationController _chipRotate;    // Rotating hint chips
  Timer? _chipTimer;
  int _chipIdx = 0;

  static const _hints = [
    ['🏠', 'odamı yeniden tasarla'],
    ['🎨', 'duvar rengi öner'],
    ['🛋️', 'bu dolaba ne yakışır?'],
    ['💡', 'bütçeye uygun dekorasyon'],
    ['✨', 'salonumu modernleştir'],
  ];

  @override
  void initState() {
    super.initState();
    // Breathing animation for Koala avatar
    _breatheCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat(reverse: true);
    // Staggered entry
    _staggerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    // Chip rotation
    _chipRotate = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300))
      ..value = 1.0;
    _chipTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _chipRotate.reverse().then((_) {
        if (!mounted) return;
        setState(() => _chipIdx = (_chipIdx + 1) % _hints.length);
        _chipRotate.forward();
      });
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _breatheCtrl.dispose();
    _staggerCtrl.dispose();
    _chipRotate.dispose();
    _chipTimer?.cancel();
    super.dispose();
  }

  // ── Navigation ──
  void _submit() {
    final t = _inputCtrl.text.trim();
    if (t.isEmpty && _pendingPhoto == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
      ChatDetailScreen(initialText: t.isNotEmpty ? t : null, initialPhoto: _pendingPhoto)));
    _inputCtrl.clear();
    setState(() => _pendingPhoto = null);
  }

  void _go(String text) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatDetailScreen(initialText: text)));

  void _startFlow(FlowState flow) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuidedFlowScreen(flow: flow)));

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  void _showPicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet(
        onCamera: () { Navigator.pop(context); _doPick(ImageSource.camera); },
        onGallery: () { Navigator.pop(context); _doPick(ImageSource.gallery); },
      ));
  }

  Future<void> _doPick(ImageSource src) async {
    final f = await _picker.pickImage(source: src, maxWidth: 1920, imageQuality: 85);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    _startFlow(FlowBuilder.buildRoomRenovation());
  }

  // ── Stagger helper ──
  Widget _staggered(int index, Widget child) {
    final delay = (index * 0.12).clamp(0.0, 1.0);
    final end = (delay + 0.4).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(delay, end, curve: Curves.easeOutCubic));
    return FadeTransition(opacity: anim,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(anim),
        child: child));
  }

  @override
  Widget build(BuildContext context) {
    final btm = MediaQuery.of(context).padding.bottom;
    final user = FirebaseAuth.instance.currentUser;
    final inputH = _pendingPhoto != null ? 114.0 : 62.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _Tok.bg,
        body: Stack(children: [
          // ── Ambient gradient blob ──
          Positioned(top: -80, right: -60,
            child: Container(width: 260, height: 260,
              decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _Tok.accent.withOpacity(0.06), _Tok.accent.withOpacity(0.0)])))),
          Positioned(bottom: 100, left: -40,
            child: Container(width: 200, height: 200,
              decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _Tok.terracotta.withOpacity(0.05), _Tok.terracotta.withOpacity(0.0)])))),

          // ── Scrollable content ──
          Positioned.fill(
            bottom: inputH + btm,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Header ──
                SliverToBoxAdapter(child: _staggered(0, _buildHeader(user))),

                // ── Hero section ──
                SliverToBoxAdapter(child: _staggered(1, _buildHero())),

                // ═══════════════════════════════════
                // BENTO GRID — Hızlı Başla
                // ═══════════════════════════════════
                SliverToBoxAdapter(child: _staggered(2, _sectionTitle('Hızlı Başla'))),
                SliverToBoxAdapter(child: _staggered(3, _buildQuickStart())),

                // ═══════════════════════════════════
                // İLHAM — Masonry grid
                // ═══════════════════════════════════
                SliverToBoxAdapter(child: _staggered(4, _sectionTitle('İlham Al'))),
                SliverToBoxAdapter(child: _staggered(5, _buildInspoGrid())),

                // ═══════════════════════════════════
                // KEŞFET — Interactive cards
                // ═══════════════════════════════════
                SliverToBoxAdapter(child: _staggered(6, _sectionTitle('Keşfet'))),
                SliverToBoxAdapter(child: _staggered(7, _buildDiscoverRow())),

                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            ),
          ),

          // ── Input bar ──
          Positioned(left: 0, right: 0, bottom: 0,
            child: _buildInputBar(btm)),
        ])));
  }

  // ═══════════════════════════════════════════════════════════
  // HEADER — Greeting + avatar
  // ═══════════════════════════════════════════════════════════
  Widget _buildHeader(User? user) {
    final name = user?.displayName?.split(' ').first ?? '';
    return SafeArea(bottom: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_greeting(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _Tok.muted)),
          if (name.isNotEmpty) Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _Tok.ink, letterSpacing: -0.5)),
        ]),
        const Spacer(),
        // Notification
        _GlassCircle(size: 38, onTap: () {},
          child: Stack(children: [
            const Icon(Icons.notifications_none_rounded, size: 19, color: _Tok.inkSoft),
            Positioned(top: 0, right: 0, child: Container(width: 7, height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _Tok.terracotta,
                border: Border.all(color: _Tok.surface, width: 1.5)))),
          ])),
        const SizedBox(width: 8),
        // Avatar
        _GlassCircle(size: 38,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          child: user?.photoURL != null
            ? ClipOval(child: Image.network(user!.photoURL!, fit: BoxFit.cover, width: 38, height: 38,
                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 18, color: _Tok.muted)))
            : const Icon(Icons.person_rounded, size: 18, color: _Tok.muted)),
      ])));
  }

  // ═══════════════════════════════════════════════════════════
  // HERO — Koala logo + rotating hints
  // ═══════════════════════════════════════════════════════════
  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Column(children: [
        // Breathing Koala mascot
        AnimatedBuilder(
          animation: _breatheCtrl,
          builder: (_, child) {
            final scale = 1.0 + 0.03 * math.sin(_breatheCtrl.value * math.pi);
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(width: 56, height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [_Tok.accent, _Tok.accentGlow]),
              boxShadow: [BoxShadow(color: _Tok.accent.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))]),
            child: const Center(child: Text('🐨', style: TextStyle(fontSize: 26))))),
        const SizedBox(height: 10),
        // Brand name with gradient
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_Tok.accent, _Tok.terracotta]).createShader(bounds),
          child: const Text('koala', style: TextStyle(
            fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1))),
        const SizedBox(height: 4),
        Text('tara · keşfet · tasarla', style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, color: _Tok.muted, letterSpacing: 1)),
        const SizedBox(height: 16),
        // Rotating hint chip
        FadeTransition(opacity: _chipRotate, child: GestureDetector(
          onTap: () => _go(_hints[_chipIdx][1]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_Tok.rPill),
              color: _Tok.surface,
              border: Border.all(color: _Tok.border),
              boxShadow: [BoxShadow(color: _Tok.shadow, blurRadius: 12, offset: const Offset(0, 4))]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_hints[_chipIdx][0], style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Text(_hints[_chipIdx][1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Tok.inkSoft)),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, size: 14, color: _Tok.accent.withOpacity(0.5)),
            ])))),
      ]));
  }

  // ═══════════════════════════════════════════════════════════
  // QUICK START — Bento grid (1 large + 2 small)
  // ═══════════════════════════════════════════════════════════
  Widget _buildQuickStart() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        // Hero CTA — Glassmorphism card
        _PressableCard(
          onTap: () => _startFlow(FlowBuilder.buildRoomRenovation()),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_Tok.r),
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF6C5CE7), Color(0xFF8B7BF7), Color(0xFFA78BFA)])),
            child: Row(children: [
              // Icon
              Container(width: 50, height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withOpacity(0.15)),
                child: const Icon(Icons.camera_alt_rounded, size: 24, color: Colors.white)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Odanı tara', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text('Fotoğraf çek → AI stilini anlasın', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7), height: 1.3)),
              ])),
              Container(width: 36, height: 36,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.15)),
                child: const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white)),
            ]))),
        const SizedBox(height: 10),
        // Two mini cards
        Row(children: [
          Expanded(child: _BentoMini(
            emoji: '💰', title: 'Bütçe Planla', subtitle: 'Akıllı dağılım',
            color: const Color(0xFFFFF4ED), accentColor: _Tok.terracotta,
            onTap: () => _startFlow(FlowBuilder.buildBudgetPlan()))),
          const SizedBox(width: 10),
          Expanded(child: _BentoMini(
            emoji: '👤', title: 'Tasarımcı Bul', subtitle: 'Sana uygun eşleş',
            color: const Color(0xFFEDF7ED), accentColor: _Tok.sage,
            onTap: () => _startFlow(FlowBuilder.buildDesignerMatch()))),
        ]),
      ]));
  }

  // ═══════════════════════════════════════════════════════════
  // INSPO GRID — Masonry with frosted labels
  // ═══════════════════════════════════════════════════════════
  Widget _buildInspoGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(children: [
          _InspoCard2(
            url: 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=400&q=80',
            label: 'Japandi', tag: 'Salon', h: 200,
            onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Japandi'))),
          _InspoCard2(
            url: 'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?auto=format&fit=crop&w=400&q=80',
            label: 'Modern', tag: 'Mutfak', h: 155,
            onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Modern'))),
        ])),
        const SizedBox(width: 10),
        Expanded(child: Column(children: [
          _InspoCard2(
            url: 'https://images.unsplash.com/photo-1505691938895-1758d7feb511?auto=format&fit=crop&w=400&q=80',
            label: 'Skandinav', tag: 'Yatak Odası', h: 165,
            onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Skandinav'))),
          _InspoCard2(
            url: 'https://images.unsplash.com/photo-1540518614846-7eded433c457?auto=format&fit=crop&w=400&q=80',
            label: 'Bohem', tag: 'Oturma', h: 190,
            onTap: () => _startFlow(FlowBuilder.buildStyleExplore('Bohem'))),
        ])),
      ]));
  }

  // ═══════════════════════════════════════════════════════════
  // DISCOVER ROW — Trend + Poll + Fact
  // ═══════════════════════════════════════════════════════════
  Widget _buildDiscoverRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(children: [
          // Trend colors card
          _PressableCard(
            onTap: () => _startFlow(FlowBuilder.buildColorAdvice()),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_Tok.r),
                color: _Tok.surface,
                border: Border.all(color: _Tok.border),
                boxShadow: [BoxShadow(color: _Tok.shadow, blurRadius: 12, offset: const Offset(0, 4))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 24, height: 24,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: _Tok.accentSoft),
                    child: const Center(child: Text('🎨', style: TextStyle(fontSize: 12)))),
                  const SizedBox(width: 8),
                  Text('2026 Trend', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _Tok.accent.withOpacity(0.7))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _colorSwatch(const Color(0xFFC4704A)),
                  const SizedBox(width: 6),
                  _colorSwatch(const Color(0xFF8B9E6B)),
                  const SizedBox(width: 6),
                  _colorSwatch(const Color(0xFFE8D5C4)),
                  const SizedBox(width: 6),
                  _colorSwatch(const Color(0xFF6C5CE7)),
                ]),
                const SizedBox(height: 10),
                Text('Odana uygula →', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Tok.accent)),
              ]))),
          const SizedBox(height: 10),
          // Fact card
          _FactCard2('🌿', 'Bitkiler odadaki stresi %37 azaltıyor'),
        ])),
        const SizedBox(width: 10),
        Expanded(child: Column(children: [
          // Poll card
          _PollCard2(onSelect: (s) => _startFlow(FlowBuilder.buildStyleExplore(s))),
          const SizedBox(height: 10),
          _FactCard2('✨', 'Açık perdeler odayı %30 geniş gösterir'),
        ])),
      ]));
  }

  Widget _colorSwatch(Color c) => Expanded(
    child: Container(height: 28,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: c)));

  // ═══════════════════════════════════════════════════════════
  // SECTION TITLE
  // ═══════════════════════════════════════════════════════════
  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
    child: Row(children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _Tok.ink, letterSpacing: -0.3)),
      const Spacer(),
      Text('Tümü →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Tok.accent)),
    ]));

  // ═══════════════════════════════════════════════════════════
  // INPUT BAR — Frosted glass
  // ═══════════════════════════════════════════════════════════
  Widget _buildInputBar(double btm) {
    final has = _inputCtrl.text.isNotEmpty || _pendingPhoto != null;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: _Tok.bg.withOpacity(0.85),
            border: Border(top: BorderSide(color: _Tok.border))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Photo preview
            if (_pendingPhoto != null) Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: _Tok.surface,
                border: Border.all(color: _Tok.border)),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_pendingPhoto!, width: 40, height: 40, fit: BoxFit.cover)),
                const SizedBox(width: 10),
                Expanded(child: Text('Fotoğraf hazır – metin ekle veya gönder',
                  style: TextStyle(fontSize: 11.5, color: _Tok.muted))),
                GestureDetector(onTap: () => setState(() => _pendingPhoto = null),
                  child: Icon(Icons.close_rounded, size: 18, color: _Tok.muted)),
              ])),
            // Input row
            Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, btm + 10),
              child: Container(height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_Tok.rPill),
                  color: _Tok.surface,
                  border: Border.all(color: _Tok.border),
                  boxShadow: [BoxShadow(color: _Tok.shadow, blurRadius: 8, offset: const Offset(0, 2))]),
                child: Row(children: [
                  // Add button
                  GestureDetector(onTap: _showPicker, child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(width: 36, height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _Tok.accentSoft),
                      child: const Icon(Icons.add_rounded, size: 20, color: _Tok.accent)))),
                  // Text field
                  Expanded(child: TextField(controller: _inputCtrl,
                    decoration: InputDecoration(
                      hintText: _pendingPhoto != null ? 'Ne sormak istersin?' : 'Koala\'ya sor...',
                      hintStyle: TextStyle(fontSize: 14, color: _Tok.muted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                    style: const TextStyle(fontSize: 14, color: _Tok.ink),
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) => setState(() {}))),
                  // Send button
                  GestureDetector(
                    onTap: has ? _submit : null,
                    child: Padding(padding: const EdgeInsets.only(right: 6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36, height: 36,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          gradient: has
                            ? const LinearGradient(colors: [_Tok.accent, _Tok.accentGlow])
                            : null,
                          color: has ? null : Colors.transparent),
                        child: Icon(Icons.arrow_upward_rounded, size: 18,
                          color: has ? Colors.white : _Tok.muted)))),
                ]))),
          ]))));
  }
}

// ═══════════════════════════════════════════════════════════
// REUSABLE COMPONENTS — 2026 Style
// ═══════════════════════════════════════════════════════════

/// Glass circle button (notification, avatar)
class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.size, required this.child, this.onTap});
  final double size;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _Tok.surface,
        border: Border.all(color: _Tok.border),
        boxShadow: [BoxShadow(color: _Tok.shadow, blurRadius: 8, offset: const Offset(0, 2))]),
      child: Center(child: child)));
}

/// Pressable card with scale animation
class _PressableCard extends StatefulWidget {
  const _PressableCard({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _pressed = true),
    onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); HapticFeedback.lightImpact(); },
    onTapCancel: () => setState(() => _pressed = false),
    child: AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: widget.child));
}

/// Bento mini card (small CTA)
class _BentoMini extends StatelessWidget {
  const _BentoMini({required this.emoji, required this.title, required this.subtitle,
    required this.color, required this.accentColor, required this.onTap});
  final String emoji, title, subtitle;
  final Color color, accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _PressableCard(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_Tok.r),
        color: _Tok.surface,
        border: Border.all(color: _Tok.border),
        boxShadow: [BoxShadow(color: _Tok.shadow, blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18)))),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _Tok.ink)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 11, color: _Tok.muted)),
      ])));
}

/// Inspo card v2 — frosted glass label
class _InspoCard2 extends StatelessWidget {
  const _InspoCard2({required this.url, required this.label, required this.tag,
    required this.h, required this.onTap});
  final String url, label, tag;
  final double h;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _PressableCard(onTap: onTap,
      child: Container(height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_Tok.r),
          boxShadow: [BoxShadow(color: _Tok.shadow, blurRadius: 12, offset: const Offset(0, 4))]),
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(_Tok.r),
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: _Tok.accentSoft),
              errorWidget: (_, __, ___) => Container(color: _Tok.accentSoft))),
          // Gradient overlay
          Container(decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_Tok.r),
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
              stops: const [0.4, 1]))),
          // Frosted tag pill
          Positioned(top: 10, left: 10,
            child: ClipRRect(borderRadius: BorderRadius.circular(_Tok.rPill),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  color: Colors.white.withOpacity(0.2),
                  child: Text(tag, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)))))),
          // Label
          Positioned(bottom: 12, left: 14,
            child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3))),
        ]))));
}

/// Fact card v2
class _FactCard2 extends StatelessWidget {
  const _FactCard2(this.emoji, this.fact);
  final String emoji, fact;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(_Tok.r),
      color: _Tok.surface,
      border: Border.all(color: _Tok.border),
      boxShadow: [BoxShadow(color: _Tok.shadow, blurRadius: 8, offset: const Offset(0, 2))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text('Biliyor muydun?', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _Tok.muted)),
      ]),
      const SizedBox(height: 8),
      Text(fact, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _Tok.ink, height: 1.4)),
    ]));
}

/// Poll card v2 — minimal, chip-based
class _PollCard2 extends StatelessWidget {
  const _PollCard2({required this.onSelect});
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(_Tok.r),
      color: _Tok.surface,
      border: Border.all(color: _Tok.border),
      boxShadow: [BoxShadow(color: _Tok.shadow, blurRadius: 8, offset: const Offset(0, 2))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('🎯  Senin tarzın?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _Tok.ink)),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6,
        children: ['Minimalist', 'Bohem', 'Japandi', 'Modern'].map((o) =>
          GestureDetector(onTap: () { HapticFeedback.selectionClick(); onSelect(o); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_Tok.rPill),
                color: _Tok.accentSoft,
                border: Border.all(color: _Tok.accent.withOpacity(0.15))),
              child: Text(o, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Tok.accent))))).toList()),
    ]));
}

/// Picker bottom sheet — frosted glass
class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.onCamera, required this.onGallery});
  final VoidCallback onCamera, onGallery;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.grey.shade300)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _PickBtn2(Icons.camera_alt_rounded, 'Kamera', onCamera)),
            const SizedBox(width: 12),
            Expanded(child: _PickBtn2(Icons.photo_library_rounded, 'Galeri', onGallery)),
          ]),
        ]))));
}

class _PickBtn2 extends StatelessWidget {
  const _PickBtn2(this.icon, this.label, this.onTap);
  final IconData icon; final String label; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _PressableCard(onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _Tok.accentSoft,
        border: Border.all(color: _Tok.accent.withOpacity(0.1))),
      child: Column(children: [
        Icon(icon, size: 28, color: _Tok.accent),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Tok.inkSoft)),
      ])));
}
'''

# ═══════════════════════════════════════════════════════════════
# Write
# ═══════════════════════════════════════════════════════════════
print("=" * 60)
print("KOALA HOME v2 — 2026 Design Iteration")
print("=" * 60)

for rel_path, content in files.items():
    full_path = os.path.join(BASE, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  ✅ {rel_path}")

print()
print("Tasarım değişiklikleri:")
print("  🎨 Warm cream background (FAF8F5) — beyazdan daha premium")
print("  🪟 Glassmorphism input bar + picker sheet (BackdropFilter)")
print("  🌊 Ambient gradient blobs (mor + terracotta)")
print("  📦 Bento grid layout (asimetrik kartlar)")
print("  👆 Pressable cards (scale 0.97 + haptic feedback)")
print("  🐨 Breathing Koala mascot (sine wave scale)")
print("  ✨ Gradient brand text (koala)")
print("  🏷️ Frosted glass tag pills on inspo cards")
print("  ⏰ Time-based greeting (Günaydın/İyi günler/İyi akşamlar)")
print("  🎭 Staggered card entry animations")
print("  🌑 Soft depth: subtle shadows + borders (not flat)")
print()
print("Test: flutter run -d chrome")
