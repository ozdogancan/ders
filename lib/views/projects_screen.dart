import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../widgets/koala_widgets.dart';
import 'chat_detail_screen.dart';

// Alias for backward compat
class _K {
  static const bg = KoalaColors.bg;
  static const card = KoalaColors.surface;
  static const accent = KoalaColors.accent;
  static const accentDark = KoalaColors.accentDark;
  static const green = KoalaColors.green;
  static const greenLight = KoalaColors.greenLight;
  static const greenDark = KoalaColors.greenDark;
  static const text = KoalaColors.text;
  static const textSec = KoalaColors.textSec;
  static const textTer = KoalaColors.textTer;
  static const border = KoalaColors.border;
}

// ─── Message types ───
enum _MsgType { koalaText, koalaProjects, koalaChips, userText }

class _Msg {
  final _MsgType type;
  final String? text;
  final List<String>? chips;
  final List<Map<String, dynamic>>? projects;
  final List<_ProjectReason>? reasons;
  _Msg({required this.type, this.text, this.chips, this.projects, this.reasons});
}

class _ProjectReason {
  final Map<String, dynamic> project;
  final String reason;
  _ProjectReason(this.project, this.reason);
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  List<Map<String, dynamic>> _allProjects = [];
  final List<_Msg> _messages = [];
  bool _loading = true;
  bool _typing = false;
  String? _error;

  // Detail views
  Map<String, dynamic>? _detailProject;
  Map<String, dynamic>? _detailProduct;
  Map<String, dynamic>? _detailDesigner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!EvlumbaLiveService.isReady) {
      final ready = await EvlumbaLiveService.waitForReady();
      if (!ready) {
        if (mounted) setState(() => _loading = false);
        return;
      }
    }
    setState(() { _loading = true; });
    try {
      final raw = await EvlumbaLiveService.getProjects(limit: 40);
      // Enrich with designer + products
      final enriched = await Future.wait(raw.map((p) async {
        final next = Map<String, dynamic>.from(p);
        final designerId = (p['designer_id'] ?? '').toString();
        try {
          if (designerId.isNotEmpty) {
            final d = await EvlumbaLiveService.getDesigner(designerId);
            if (d != null) next['profiles'] = d;
          }
        } catch (_) {}
        try {
          final pid = (p['id'] ?? '').toString();
          if (pid.isNotEmpty) {
            final links = await EvlumbaLiveService.getProjectShopLinks(pid);
            next['products'] = links.map((l) => <String, dynamic>{
              ...l,
              'name': l['product_title'] ?? l['name'] ?? l['title'] ?? 'Ürün',
              'brand': l['brand'] ?? l['product_brand'] ?? '',
              'price': l['product_price'] ?? l['price'] ?? '',
              'image_url': l['product_image_url'] ?? l['image_url'] ?? '',
              'url': l['product_url'] ?? l['url'] ?? l['link'] ?? '',
            }).toList();
          }
        } catch (_) {}
        return next;
      }));

      if (!mounted) return;
      setState(() { _allProjects = enriched; _loading = false; });
      _startConversation();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _startConversation() {
    _addMsg(_Msg(
      type: _MsgType.koalaText,
      text: 'Merhaba! Evini güzelleştirmek için buradayım. Sana en uygun tasarımları ve ürünleri bulmak istiyorum.',
    ));
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _addMsg(_Msg(
        type: _MsgType.koalaChips,
        text: 'Hangi odanı dönüştürmek istiyorsun?',
        chips: [
          '🛋️ Salon',
          '🛏️ Yatak Odası',
          '🍳 Mutfak',
          '🚿 Banyo',
          '💻 Çalışma Odası',
          '📸 Fotoğraf çekeyim',
        ],
      ));
    });
  }

  void _addMsg(_Msg msg) {
    setState(() => _messages.add(msg));
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _onChipTap(String chip) {
    HapticFeedback.lightImpact();
    _addMsg(_Msg(type: _MsgType.userText, text: chip));
    _showResults(chip);
  }

  void _onSend() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    _inputFocus.unfocus();
    HapticFeedback.lightImpact();
    _addMsg(_Msg(type: _MsgType.userText, text: text));
    _showResults(text);
  }

  void _showResults(String query) {
    setState(() => _typing = true);
    _scrollDown();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _typing = false);

      // Filter projects based on query
      final q = query.toLowerCase();
      var filtered = _allProjects.where((p) {
        final blob = [
          p['title'] ?? '', p['project_type'] ?? '', p['location'] ?? '',
          (p['tags'] as List?)?.join(' ') ?? '',
        ].join(' ').toLowerCase();
        return blob.contains(q) || q.contains('salon') || q.contains('mutfak')
            || q.contains('yatak') || q.contains('banyo') || q.contains('çalışma')
            || q.contains('fotoğraf') || q.length < 5;
      }).take(4).toList();

      if (filtered.isEmpty) filtered = _allProjects.take(3).toList();

      // Generate reasons
      final reasons = filtered.map((p) {
        final room = (p['project_type'] ?? '').toString();
        final designer = (p['profiles'] as Map?)?['full_name'] ?? '';
        final prods = (p['products'] as List?)?.length ?? 0;
        String reason;
        if (q.contains('salon')) {
          reason = 'Sıcak tonlar ve doğal malzemelerle oluşturulmuş, tam aradığın tarza uygun';
        } else if (q.contains('mutfak')) {
          reason = 'Fonksiyonel ve estetik mutfak tasarımı, günlük kullanıma uygun';
        } else if (q.contains('yatak')) {
          reason = 'Huzurlu ve dinlendirici bir yatak odası konsepti';
        } else if (prods > 0) {
          reason = '$prods ürün ile tamamlanmış, hepsine ulaşabilirsin';
        } else if (designer.isNotEmpty) {
          reason = '$designer tarafından tasarlanmış, tarzına yakın buldum';
        } else {
          reason = '$room alanında ilham verici bir proje';
        }
        return _ProjectReason(p, reason);
      }).toList();

      _addMsg(_Msg(
        type: _MsgType.koalaText,
        text: 'Evlumba\'dan ${filtered.length} proje senin için seçtim! İlgini çekene dokun, detayları keşfet.',
      ));

      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _addMsg(_Msg(
          type: _MsgType.koalaProjects,
          reasons: reasons,
        ));

        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          _addMsg(_Msg(
            type: _MsgType.koalaChips,
            text: 'Fikrini değiştirmek istersen:',
            chips: ['Daha koyu tonlar', 'Bütçem 20K altı', 'Daha minimalist', 'Başka odalar göster'],
          ));
        });
      });
    });
  }

  // ─── Data helpers ───
  String _cover(Map<String, dynamic> p) {
    for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final imgs = (p['designer_project_images'] as List?)?.whereType<Map>().toList();
    if (imgs == null || imgs.isEmpty) return '';
    imgs.sort((a, b) => ((a['sort_order'] as num?)?.toInt() ?? 9999).compareTo((b['sort_order'] as num?)?.toInt() ?? 9999));
    return (imgs.first['image_url'] ?? '').toString();
  }

  List<Map<String, dynamic>> _products(Map<String, dynamic> p) =>
      (p['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  Map<String, dynamic>? _designer(Map<String, dynamic> p) =>
      p['profiles'] as Map<String, dynamic>?;

  String _initials(String n) => n.split(' ').where((s) => s.isNotEmpty).take(2).map((s) => s[0].toUpperCase()).join();

  // ═══════════════════════════════
  // BUILD
  // ═══════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: _K.bg, body: LoadingState());
    if (_error != null) return Scaffold(backgroundColor: _K.bg, body: SafeArea(child: Column(children: [_header(), Expanded(child: _errW())])));

    // Sub-pages
    if (_detailProduct != null) return _productPage();
    if (_detailDesigner != null) return _designerPage();
    if (_detailProject != null) return _projectPage();

    return _chatPage();
  }

  // ═══ CHAT PAGE (main) ═══
  Widget _chatPage() {
    final btm = MediaQuery.of(context).padding.bottom;
    final hasText = _inputCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: _K.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(),
          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return _typingBubble();
                return _buildMsg(_messages[i]);
              },
            ),
          ),
          // Input
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, btm + 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _K.border, width: 0.5),
              ),
              child: Row(children: [
                GestureDetector(
                  onTap: () {
                    // Photo picker → chat
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatDetailScreen()));
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.04)),
                      child: const Icon(LucideIcons.image, size: 18, color: _K.textSec),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _inputFocus,
                    onSubmitted: (_) => _onSend(),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Koala\'ya sor...',
                      hintStyle: TextStyle(fontSize: 14, color: _K.textTer),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    style: const TextStyle(fontSize: 14, color: _K.text),
                  ),
                ),
                GestureDetector(
                  onTap: _onSend,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: hasText ? const LinearGradient(colors: [_K.accent, _K.accentDark]) : null,
                        color: hasText ? null : Colors.black.withValues(alpha: 0.04),
                      ),
                      child: Icon(
                        hasText ? LucideIcons.arrowUp : LucideIcons.plus,
                        size: 18,
                        color: hasText ? Colors.white : _K.textSec,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildMsg(_Msg msg) {
    switch (msg.type) {
      case _MsgType.koalaText:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _koalaAv(),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _K.card,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4), topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(color: _K.border, width: 0.5),
                ),
                child: Text(msg.text!, style: const TextStyle(fontSize: 14, color: _K.text, height: 1.55)),
              ),
            ),
          ]),
        );

      case _MsgType.koalaChips:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _koalaAv(),
            const SizedBox(width: 8),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (msg.text != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: _K.card,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4), topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18),
                      ),
                      border: Border.all(color: _K.border, width: 0.5),
                    ),
                    child: Text(msg.text!, style: const TextStyle(fontSize: 14, color: _K.text, height: 1.55)),
                  ),
                Wrap(spacing: 6, runSpacing: 6, children: msg.chips!.map((c) =>
                  GestureDetector(
                    onTap: () => _onChipTap(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: _K.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _K.border, width: 0.5),
                      ),
                      child: Text(c, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _K.text)),
                    ),
                  ),
                ).toList()),
              ]),
            ),
          ]),
        );

      case _MsgType.userText:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_K.accent, _K.accentDark]),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18), topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(msg.text!, style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.5)),
            ),
          ),
        );

      case _MsgType.koalaProjects:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14, left: 38),
          child: Column(
            children: msg.reasons!.map((r) => _projectCard(r)).toList(),
          ),
        );
    }
  }

  // ─── Project card in chat ───
  Widget _projectCard(_ProjectReason pr) {
    final p = pr.project;
    final img = _cover(p);
    final title = (p['title'] ?? 'Proje').toString();
    final room = (p['project_type'] ?? '').toString();
    final d = _designer(p);
    final dName = (d?['full_name'] ?? '').toString().trim();
    final prods = _products(p);

    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); setState(() => _detailProject = p); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _K.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _K.border, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image — clean, large
          SizedBox(
            height: 180,
            width: double.infinity,
            child: Stack(children: [
              Positioned.fill(child: _imgW(img)),
              if (room.isNotEmpty) Positioned(top: 12, left: 12, child: _pill(room)),
            ]),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _K.text), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(children: [
                if (dName.isNotEmpty) ...[
                  _miniAv(d), const SizedBox(width: 6),
                  Text(dName, style: const TextStyle(fontSize: 12, color: _K.textSec)),
                ],
                if (prods.isNotEmpty) ...[
                  if (dName.isNotEmpty) _dot(),
                  Text('${prods.length} ürün', style: const TextStyle(fontSize: 12, color: _K.textTer)),
                ],
              ]),
              // AI reason
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _K.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _K.accent.withValues(alpha: 0.1), width: 0.5),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _koalaAv(size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      pr.reason,
                      style: TextStyle(fontSize: 12, color: _K.accentDark, height: 1.45, fontStyle: FontStyle.italic),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ═══ PROJECT DETAIL PAGE ═══
  Widget _projectPage() {
    final p = _detailProject!;
    final img = _cover(p);
    final title = (p['title'] ?? 'Proje').toString();
    final location = (p['location'] ?? '').toString().trim();
    final room = (p['project_type'] ?? '').toString().trim();
    final d = _designer(p);
    final dName = (d?['full_name'] ?? '').toString().trim();
    final dCity = (d?['city'] ?? '').toString().trim();
    final dAvatar = (d?['avatar_url'] ?? '').toString().trim();
    final dId = (d?['id'] ?? p['designer_id'] ?? '').toString();
    final prods = _products(p);
    final btm = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _K.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 300, pinned: true, backgroundColor: _K.bg,
            leading: Padding(padding: const EdgeInsets.all(8), child: _backCircle(() => setState(() => _detailProject = null))),
            flexibleSpace: FlexibleSpaceBar(background: Stack(fit: StackFit.expand, children: [
              _imgW(img),
              Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x88000000)]))),
              if (room.isNotEmpty) Positioned(top: 62, left: 16, child: _pill(room)),
            ])),
          ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _K.text, letterSpacing: -0.3)),
              if (location.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(location, style: const TextStyle(fontSize: 13, color: _K.textSec))),
              // Designer
              if (dName.isNotEmpty) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () { HapticFeedback.lightImpact(); setState(() => _detailDesigner = d); },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _K.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: _K.border, width: 0.5)),
                    child: Row(children: [
                      _av(dName, dAvatar, 50), const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(dName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _K.text)),
                        if (dCity.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(dCity, style: const TextStyle(fontSize: 11, color: _K.textSec))),
                      ])),
                      const Icon(LucideIcons.chevronRight, size: 16, color: _K.textTer),
                    ]),
                  ),
                ),
              ],
              // Products
              if (prods.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('BU PROJEDE KULLANILANLAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.textTer, letterSpacing: 0.8)),
                const SizedBox(height: 12),
                ...prods.map((pr) => _prodRow(pr)),
              ],
            ]),
          )),
        ]),
        // Bottom CTA
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, btm + 16),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_K.bg.withValues(alpha: 0), _K.bg])),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (dId.isNotEmpty) launchUrl(Uri.parse('https://www.evlumba.com/tasarimci/$dId'), mode: LaunchMode.inAppBrowserView);
            },
            child: Container(
              height: 54, decoration: BoxDecoration(color: _K.green, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: _K.green.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 6))]),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(LucideIcons.messageCircle, size: 16, color: Colors.white), SizedBox(width: 8),
                Text('Tasarımcıya mesaj gönder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
              ]),
            ),
          ),
        )),
      ]),
    );
  }

  // ═══ PRODUCT PAGE ═══
  Widget _productPage() {
    final pr = _detailProduct!;
    final name = (pr['name'] ?? 'Ürün').toString();
    final brand = (pr['brand'] ?? '').toString();
    final price = (pr['price'] ?? '').toString();
    final desc = (pr['description'] ?? pr['product_description'] ?? '').toString();
    final imgUrl = (pr['image_url'] ?? '').toString();
    final url = (pr['url'] ?? pr['link'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: _K.bg,
      body: SafeArea(child: Column(children: [
        _hdr('Ürün', () => setState(() => _detailProduct = null)),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
          Container(height: 220, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: KoalaColors.surfaceAlt),
            child: Stack(fit: StackFit.expand, children: [_imgW(imgUrl), Positioned(top: 12, right: 12, child: _evBadge())])),
          const SizedBox(height: 16),
          Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _K.text)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(brand, style: const TextStyle(fontSize: 14, color: _K.textSec)),
            if (price.isNotEmpty) Text(price, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _K.text)),
          ]),
          if (desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text(desc, style: const TextStyle(fontSize: 14, color: KoalaColors.textSec, height: 1.65))),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              final target = url.isNotEmpty ? url : 'https://www.evlumba.com/kesfet?q=${Uri.encodeComponent(name)}';
              launchUrl(Uri.parse(target), mode: LaunchMode.inAppBrowserView);
            },
            child: Container(height: 56, decoration: BoxDecoration(color: _K.green, borderRadius: BorderRadius.circular(18)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Ürünü incele', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                SizedBox(width: 6), Icon(LucideIcons.externalLink, size: 14, color: Colors.white),
              ])),
          ),
        ])),
      ])),
    );
  }

  // ═══ DESIGNER PAGE ═══
  Widget _designerPage() {
    final d = _detailDesigner!;
    final name = (d['full_name'] ?? '').toString().trim();
    final city = (d['city'] ?? '').toString().trim();
    final avatar = (d['avatar_url'] ?? '').toString().trim();
    final bio = (d['about'] ?? d['bio'] ?? '').toString().trim();
    final id = (d['id'] ?? '').toString();
    final dProjects = _allProjects.where((p) { final dp = p['profiles'] as Map?; return dp?['id'] == d['id']; }).toList();

    return Scaffold(
      backgroundColor: _K.bg,
      body: SafeArea(child: Column(children: [
        _hdr('Tasarımcı', () => setState(() => _detailDesigner = null)),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
          Center(child: Column(children: [
            _av(name, avatar, 80), const SizedBox(height: 12),
            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _K.text)),
            const SizedBox(height: 4),
            Text('${d['project_count'] ?? dProjects.length} proje · $city', style: const TextStyle(fontSize: 13, color: _K.textSec)),
            if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(bio, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: KoalaColors.textSec, height: 1.6))),
          ])),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () { if (id.isNotEmpty) launchUrl(Uri.parse('https://www.evlumba.com/tasarimci/$id'), mode: LaunchMode.inAppBrowserView); },
            child: Container(height: 52, decoration: BoxDecoration(color: _K.green, borderRadius: BorderRadius.circular(16)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(LucideIcons.messageCircle, size: 16, color: Colors.white), SizedBox(width: 8),
                Text('Mesaj gönder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
              ])),
          ),
          if (dProjects.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text('PROJELERİ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.textTer, letterSpacing: 0.8)),
            const SizedBox(height: 12),
            ...dProjects.map((p) => GestureDetector(
              onTap: () => setState(() { _detailDesigner = null; _detailProject = p; }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10), clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _K.border, width: 0.5), color: _K.card),
                child: Row(children: [
                  SizedBox(width: 90, height: 72, child: _imgW(_cover(p))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text((p['title'] ?? '').toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _K.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Padding(padding: const EdgeInsets.only(top: 3), child: Text((p['project_type'] ?? '').toString(), style: const TextStyle(fontSize: 11, color: _K.textSec))),
                  ])),
                  const Padding(padding: EdgeInsets.only(right: 12), child: Icon(LucideIcons.chevronRight, size: 14, color: _K.textTer)),
                ]),
              ),
            )),
          ],
        ])),
      ])),
    );
  }

  // ═══ SHARED WIDGETS ═══
  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Row(children: [
      _backCircle(() => Navigator.pop(context)),
      const SizedBox(width: 10),
      _koalaAv(size: 28),
      const SizedBox(width: 8),
      const Expanded(child: Text('Keşfet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _K.text))),
    ]),
  );

  Widget _hdr(String title, VoidCallback onBack) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Row(children: [
      _backCircle(onBack),
      Expanded(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _K.text))),
      const SizedBox(width: 40),
    ]),
  );

  Widget _backCircle(VoidCallback onTap) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.8), border: Border.all(color: _K.border, width: 0.5)),
      child: const Icon(LucideIcons.arrowLeft, size: 18, color: _K.text)),
  );

  Widget _koalaAv({double size = 28}) => Container(
    width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [_K.green, _K.greenDark])),
    child: Center(child: Text('K', style: TextStyle(fontSize: size * 0.46, fontWeight: FontWeight.w600, color: Colors.white))),
  );

  Widget _typingBubble() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _koalaAv(),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(color: _K.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _K.border, width: 0.5)),
        child: const _TypingDots(),
      ),
    ]),
  );

  Widget _prodRow(Map<String, dynamic> pr) {
    final name = (pr['name'] ?? 'Ürün').toString();
    final brand = (pr['brand'] ?? '').toString();
    final price = (pr['price'] ?? '').toString();
    final imgUrl = (pr['image_url'] ?? '').toString();
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); setState(() => _detailProduct = pr); },
      child: Container(
        padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: _K.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _K.border, width: 0.5)),
        child: Row(children: [
          _thumb(imgUrl, 52), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _K.text), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Row(children: [
              if (brand.isNotEmpty) Text(brand, style: const TextStyle(fontSize: 11, color: _K.textSec)),
              if (brand.isNotEmpty) const SizedBox(width: 6),
              _evBadgeSmall(),
            ]),
          ])),
          if (price.isNotEmpty) Text(price, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _K.text)),
          const SizedBox(width: 8),
          const Icon(LucideIcons.chevronRight, size: 14, color: _K.textTer),
        ]),
      ),
    );
  }

  Widget _pill(String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(20)),
    child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _K.text)));

  Widget _evBadge() => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: _K.green)),
      const SizedBox(width: 4), const Text('evlumba', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _K.greenDark)),
    ]));

  Widget _evBadgeSmall() => Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: _K.greenLight, borderRadius: BorderRadius.circular(4)),
    child: const Text('evlumba', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: _K.greenDark)));

  Widget _av(String name, String url, double sz) => Container(width: sz, height: sz,
    decoration: BoxDecoration(shape: BoxShape.circle, color: KoalaColors.surfaceAlt,
      image: url.isNotEmpty ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null),
    child: url.isEmpty ? Center(child: Text(_initials(name), style: TextStyle(fontSize: sz * 0.32, fontWeight: FontWeight.w600, color: KoalaColors.textMed))) : null);

  Widget _miniAv(Map<String, dynamic>? d) {
    final n = (d?['full_name'] ?? '').toString(); final a = (d?['avatar_url'] ?? '').toString();
    return Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: KoalaColors.surfaceAlt,
      image: a.isNotEmpty ? DecorationImage(image: NetworkImage(a), fit: BoxFit.cover) : null),
      child: a.isEmpty ? Center(child: Text(_initials(n), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: KoalaColors.textMed))) : null);
  }

  Widget _thumb(String url, double sz) => Container(width: sz, height: sz, clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(sz * 0.27), color: KoalaColors.surfaceAlt),
    child: url.isNotEmpty ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph()) : _ph());

  Widget _imgW(String url) {
    if (url.isEmpty) return Container(color: KoalaColors.surfaceAlt, child: _ph());
    return Image.network(url, fit: BoxFit.cover,
      loadingBuilder: (_, c, p) => p == null ? c : Container(color: KoalaColors.surfaceAlt),
      errorBuilder: (_, __, ___) => Container(color: KoalaColors.surfaceAlt, child: _ph()));
  }

  Widget _ph() => const Center(child: Icon(LucideIcons.image, size: 32, color: _K.textTer));

  Widget _dot() => Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: _K.textTer)));

  Widget _errW() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(LucideIcons.wifiOff, size: 40, color: _K.textTer), const SizedBox(height: 12),
    Text(_error ?? 'Yüklenemedi', style: const TextStyle(fontSize: 14, color: _K.textSec)),
    const SizedBox(height: 16),
    GestureDetector(onTap: _load, child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(color: _K.accent, borderRadius: BorderRadius.circular(16)),
      child: const Text('Tekrar dene', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)))),
  ]));
}

// ─── Typing dots ───
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _c;

  @override
  void initState() {
    super.initState();
    _c = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true));
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () { if (mounted) _c[i].forward(); });
    }
  }

  @override
  void dispose() { for (final c in _c) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => AnimatedBuilder(animation: _c[i],
      builder: (_, __) => Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: Color.lerp(KoalaColors.accentLight, _K.accent, _c[i].value))))));
}
