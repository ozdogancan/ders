import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart' show sha1;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/theme/koala_tokens.dart';
import '../../services/saved_items_service.dart';
import 'widgets/pro_match_sheet.dart';

/// "Bu Tasarımı Gerçeğe Dönüştür" — sade & odaklı 2-sekme yapı:
///   • Ürünler — AI'ın bu tasarımda kullandığı ürünler (fiyat + link)
///   • Profesyonele Sor — bu tasarıma en uygun 3 iç mimar
/// Üst: kompakt hero görsel + chip'ler. Alt: tek primary CTA (sekme'ye göre
/// içerik) + Sakla ikincil aksiyon.
class RealizeScreen extends StatefulWidget {
  final String afterSrc;
  final String room;        // Türkçe: "Mutfak"
  final String theme;       // Türkçe: "Minimalist"
  final String themeValue;  // İngilizce slug: "minimalist"
  final String roomTypeTr;  // Pro match için: "Mutfak"
  /// Swipe akışından geldiyse o tasarımı yapan tasarımcının ID'si.
  final String? preferredDesignerId;

  const RealizeScreen({
    super.key,
    required this.afterSrc,
    required this.room,
    required this.theme,
    required this.themeValue,
    required this.roomTypeTr,
    this.preferredDesignerId,
  });

  @override
  State<RealizeScreen> createState() => _RealizeScreenState();
}

class _RealizeScreenState extends State<RealizeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final String _itemId = sha1
      .convert('realize|${widget.afterSrc}|${widget.themeValue}'.codeUnits)
      .toString()
      .substring(0, 24);

  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
    // Ürünler "çok yakında" — API çağrısı kaldırıldı.
  }

  void _onTabChanged() {
    // Sadece bottom CTA değişimi için minimal setState — hero kart rebuild
    // olmasın diye RepaintBoundary + AnimatedSwitcher değil, direkt setState
    // ama hero zaten static const ile sabitlenmiş.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _saveToCollection() async {
    if (_saving || _saved) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saklamak için giriş yap')),
      );
      return;
    }
    setState(() => _saving = true);
    // item_type='project' → Projelerim'de görünsün, kind='ai_design' → AI üretimi.
    final ok = await SavedItemsService.saveItem(
      type: SavedItemType.project,
      itemId: _itemId,
      title: 'Gerçeğe Dönüştürülecek · ${widget.room}',
      imageUrl: widget.afterSrc,
      subtitle: 'Gerçeğe Dönüştür · ${widget.theme}',
      extraData: {
        'kind': 'ai_design',
        'ai_generated': true,
        'room': widget.room,
        'style': widget.theme,
        'theme': widget.theme,
        'after_url': widget.afterSrc,
        'category': 'realize_request',
        'saved_at': DateTime.now().toIso8601String(),
      },
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok;
    });
    if (ok) {
      _toast('Listeye eklendi', LucideIcons.bookmark);
    } else {
      _toast('Kaydedilemedi', LucideIcons.x);
    }
  }

  void _askPro() {
    HapticFeedback.selectionClick();
    ProMatchSheet.show(
      context,
      restyleUrl: widget.afterSrc,
      roomType: widget.roomTypeTr,
      theme: widget.themeValue.toLowerCase(),
      city: null,
      preferredDesignerId: widget.preferredDesignerId,
    );
  }

  void _toast(String msg, IconData icon) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: KoalaColors.text.withValues(alpha: 0.92),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        content: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 10),
            Text(msg,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            // Hero ve tab segment'i RepaintBoundary'de sabitle — tab geçişi
            // sırasında hero görseli rebuild olmasın.
            const RepaintBoundary(child: SizedBox.shrink()),
            RepaintBoundary(child: _hero()),
            RepaintBoundary(child: _segmentTabs()),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _proView(),
                  _productsView(),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.x, color: KoalaColors.text),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Gerçeğe Dönüştür',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: KoalaColors.text,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Üst hero — ufak boyutlu, içerik için yer bırak. Fotoğraf solda square,
  /// yanında özet (oda + stil + tek satır intent).
  Widget _hero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: KoalaColors.border, width: 0.6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 96,
                height: 96,
                child: _afterImage(widget.afterSrc),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _SmallChip(
                          icon: LucideIcons.home,
                          label: widget.room,
                          tinted: true),
                      _SmallChip(
                          icon: LucideIcons.palette, label: widget.theme),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bu tasarımı evine getir',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.text,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ürün satın al ya da bir iç mimara devret.',
                    style: TextStyle(
                      fontSize: 12,
                      color: KoalaColors.textSec,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: KoalaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(KoalaRadius.pill),
        ),
        child: TabBar(
          controller: _tabs,
          indicator: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(KoalaRadius.pill),
            boxShadow: KoalaShadows.card,
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: KoalaColors.accentDeep,
          unselectedLabelColor: KoalaColors.textSec,
          labelStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.users, size: 14),
                  SizedBox(width: 6),
                  Text('Profesyonele Sor'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.shoppingBag, size: 14),
                  SizedBox(width: 6),
                  Text('Ürünler'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productsView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 3D-ish layered illustration
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 16,
                    top: 28,
                    child: Transform.rotate(
                      angle: -0.18,
                      child: Container(
                        width: 80,
                        height: 100,
                        decoration: BoxDecoration(
                          color: KoalaColors.accentSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 28,
                    child: Transform.rotate(
                      angle: 0.18,
                      child: Container(
                        width: 80,
                        height: 100,
                        decoration: BoxDecoration(
                          color: KoalaColors.accentDeep,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Icon(LucideIcons.shoppingBag,
                              size: 28, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 88,
                    height: 110,
                    decoration: BoxDecoration(
                      color: KoalaColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: KoalaColors.border, width: 0.6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(LucideIcons.tag,
                          size: 30, color: KoalaColors.accentDeep),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Çok Yakında',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: KoalaColors.text,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'AI bu tasarımdaki tüm ürünleri tek tıkla\nsipariş edebileceğin şekilde sunacak.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: KoalaColors.textSec,
                height: 1.5,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: KoalaColors.accentSoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.sparkles,
                      size: 12, color: KoalaColors.accentDeep),
                  SizedBox(width: 6),
                  Text(
                    'Geliştiriliyor',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.accentDeep,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _proView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  KoalaColors.accentSoft,
                  KoalaColors.accentSoft.withValues(alpha: 0.5),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: KoalaColors.accentDeep,
                      ),
                      child: const Icon(LucideIcons.users,
                          size: 22, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Bu tasarıma uygun profesyoneller',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.accentDeep,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Stilini ve mekanını analiz edip portföy uyumuna göre en '
                  'uygun profesyonelleri önereceğiz. Birini seçip portföyünü '
                  'gör, doğrudan mesaj at.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: KoalaColors.text,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _ProBadge(icon: LucideIcons.shieldCheck, label: 'Doğrulanmış'),
                    const SizedBox(width: 8),
                    _ProBadge(icon: LucideIcons.star, label: 'Yüksek puanlı'),
                    const SizedBox(width: 8),
                    _ProBadge(icon: LucideIcons.zap, label: 'Hızlı yanıt'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Süreç adımları
          _StepRow(
            n: '1',
            title: 'Tasarımcıları gör',
            sub: 'Portföyleri ve önceki projeleri incele',
          ),
          const SizedBox(height: 10),
          _StepRow(
            n: '2',
            title: 'Mesaj at',
            sub: 'Detayları konuş, fiyat al',
          ),
          const SizedBox(height: 10),
          _StepRow(
            n: '3',
            title: 'Tasarımı gerçekleştir',
            sub: 'Tasarımcı senin yerine yönetir',
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final onProTab = _tabs.index == 0; // Profesyonele Sor varsayılan
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: KoalaColors.bg,
          border: Border(
              top: BorderSide(color: KoalaColors.border, width: 0.5)),
        ),
        child: SizedBox(
          height: 54,
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: KoalaColors.accentDeep,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: onProTab ? _askPro : null,
            icon: Icon(
              onProTab ? LucideIcons.messageCircle : LucideIcons.clock,
              size: 18,
            ),
            label: Text(
              onProTab ? 'Profesyonelleri Gör' : 'Çok yakında',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _afterImage(String s) {
    if (s.startsWith('data:image')) {
      try {
        final commaIdx = s.indexOf(',');
        final b = base64Decode(s.substring(commaIdx + 1));
        return Image.memory(b, fit: BoxFit.cover);
      } catch (_) {
        return Container(color: KoalaColors.surfaceAlt);
      }
    }
    return CachedNetworkImage(
      imageUrl: s,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(color: KoalaColors.surfaceAlt),
      errorWidget: (_, _, _) => Container(color: KoalaColors.surfaceAlt),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.icon,
    required this.label,
    this.tinted = false,
  });
  final IconData icon;
  final String label;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tinted ? KoalaColors.accentSoft : KoalaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 11,
              color:
                  tinted ? KoalaColors.accentDeep : KoalaColors.textSec),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tinted ? KoalaColors.accentDeep : KoalaColors.text,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: KoalaColors.accentDeep),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: KoalaColors.accentDeep,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.n, required this.title, required this.sub});
  final String n;
  final String title;
  final String sub;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KoalaColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KoalaColors.accentSoft,
            ),
            child: Text(
              n,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: KoalaColors.accentDeep,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: KoalaColors.textSec,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Product {
  final String title;
  final String imageUrl;
  final String price;
  final String url;
  final String? brand;

  const _Product({
    required this.title,
    required this.imageUrl,
    required this.price,
    required this.url,
    this.brand,
  });

  factory _Product.parse(Map<String, dynamic> j) {
    return _Product(
      title: (j['title'] ?? j['name'] ?? '').toString(),
      imageUrl: (j['image_url'] ?? j['image'] ?? '').toString(),
      price: (j['price'] ?? '').toString(),
      url: (j['url'] ?? '').toString(),
      brand: (j['brand'] ?? j['merchant']) as String?,
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.p});
  final _Product p;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(p.url);
    if (uri == null) return;
    HapticFeedback.selectionClick();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: p.url));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı kopyalandı')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(context),
        child: Container(
          decoration: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KoalaColors.border, width: 0.6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: p.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: KoalaColors.surfaceAlt),
                      errorWidget: (_, _, _) =>
                          Container(color: KoalaColors.surfaceAlt),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        child: const Icon(
                          LucideIcons.externalLink,
                          size: 13,
                          color: KoalaColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: KoalaColors.text,
                        height: 1.3,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p.price.isNotEmpty ? p.price : '—',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.accentDeep,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
