content = """import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/credit_service.dart';
import '../services/evlumba_service.dart';
import '../stores/scan_store.dart';
import '../models/scan_analysis.dart';
import '../widgets/koala_logo.dart';
import 'profile_screen.dart';
import 'credit_store_screen.dart';

class ScanHomeScreen extends ConsumerStatefulWidget {
  const ScanHomeScreen({super.key});
  @override
  ConsumerState<ScanHomeScreen> createState() => _ScanHomeScreenState();
}

class _ScanHomeScreenState extends ConsumerState<ScanHomeScreen> with SingleTickerProviderStateMixin {
  final CreditService _creditService = CreditService();
  int _credits = 0;
  bool _isLoading = true;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    ScanStore.instance.addListener(_onStore);
    _loadCredits();
    _initLoad();
  }

  @override
  void dispose() {
    ScanStore.instance.removeListener(_onStore);
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    setState(() => _isLoading = true);
    await ScanStore.instance.loadFromSupabase(force: true);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadCredits() async {
    final c = await _creditService.getCredits();
    if (mounted) setState(() => _credits = c);
  }

  void _onStore() {
    if (!mounted) return;
    _loadCredits();
    setState(() {});
  }

  void _openProfile() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
    _loadCredits();
  }

  void _openCreditStore() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreditStoreScreen()));
    _loadCredits();
  }

  void _goToScanTab() {
    // MainShell'deki tab'a gecis - parent widget uzerinden
    final shell = context.findAncestorStateOfType<State>();
    // Basit cozum: bottom nav index'i 1'e cek
    // Bu MainShell'deki _onTabTapped(1) ile ayni isi yapar
  }

  @override
  Widget build(BuildContext context) {
    final scans = ScanStore.instance.scans;
    final hasScans = scans.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)))
          : CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              if (!hasScans)
                SliverToBoxAdapter(child: _buildEmptyState())
              else
                SliverToBoxAdapter(child: _buildScanList(scans)),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(children: [
        KoalaLogo(size: 40),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Koala', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5)),
          Text('by evlumba', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: _openCreditStore,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF6C5CE7).withOpacity(0.06),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.1))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6C5CE7)),
              const SizedBox(width: 4),
              Text('$_credits', style: const TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.w800, fontSize: 14)),
            ]))),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openProfile,
          child: Builder(builder: (_) {
            final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
            return Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: photoUrl == null ? const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)]) : null,
                border: photoUrl != null ? Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.2), width: 2) : null),
              child: photoUrl != null
                ? ClipOval(child: Image.network(photoUrl, width: 38, height: 38, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 18)))
                : const Icon(Icons.person_rounded, color: Colors.white, size: 18));
          }),
        ),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(children: [
        // Koala hero
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform.scale(scale: 0.85 + 0.15 * v, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
          child: Image.asset('assets/images/koala_hero.png', height: 120)),
        const SizedBox(height: 16),
        const Text('Ho\\u015f geldin!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text('Mekan\\u0131n\\u0131n foto\\u011fraf\\u0131n\\u0131 \\u00e7ek,\\nKoala stilini analiz etsin',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.grey.shade500, height: 1.5)),
        const SizedBox(height: 28),

        // CTA Card
        GestureDetector(
          onTap: _goToScanTab,
          child: Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 8))]),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white.withOpacity(0.2)),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Mekan\\u0131n\\u0131 Tara', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 3),
                Text('Foto\\u011fraf \\u00e7ek, saniyeler i\\u00e7inde analiz al',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7))),
              ])),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.5), size: 24),
            ]),
          ),
        ),
        const SizedBox(height: 24),

        // Oda tipi pilleri
        Wrap(spacing: 8, runSpacing: 8, children: const [
          _RoomPill(emoji: '\\ud83c\\udfe0', label: 'Salon', color: Color(0xFF6C5CE7)),
          _RoomPill(emoji: '\\ud83c\\udf73', label: 'Mutfak', color: Color(0xFFEC4899)),
          _RoomPill(emoji: '\\ud83d\\udecf\\ufe0f', label: 'Yatak Odas\\u0131', color: Color(0xFF00B894)),
          _RoomPill(emoji: '\\ud83d\\udebf', label: 'Banyo', color: Color(0xFF38BDF8)),
          _RoomPill(emoji: '\\ud83d\\udcbc', label: 'Ofis', color: Color(0xFFF59E0B)),
        ]),
        const SizedBox(height: 28),

        // Nasil calisir
        Align(
          alignment: Alignment.centerLeft,
          child: Text('NASIL \\u00c7ALI\\u015eIR',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade400, letterSpacing: 1))),
        const SizedBox(height: 14),
        Row(children: const [
          _HowCard(icon: Icons.camera_alt_rounded, color: Color(0xFF6C5CE7), title: '\\u00c7ek', desc: 'Mekan\\u0131n foto\\u011fraf\\u0131n\\u0131 \\u00e7ek'),
          SizedBox(width: 10),
          _HowCard(icon: Icons.auto_awesome, color: Color(0xFFEC4899), title: 'Analiz', desc: 'Koala stilini analiz etsin'),
          SizedBox(width: 10),
          _HowCard(icon: Icons.explore_rounded, color: Color(0xFF00B894), title: 'Ke\\u015ffet', desc: "evlumba'da ke\\u015ffet"),
        ]),
      ]),
    );
  }

  Widget _buildScanList(List<LocalScan> scans) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Taramalar\\u0131n', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF6C5CE7).withOpacity(0.08), borderRadius: BorderRadius.circular(99)),
            child: Text('${scans.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6C5CE7)))),
        ]),
        const SizedBox(height: 14),
        ...scans.map((scan) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ScanTile(scan: scan, onTap: () {
            ScanStore.instance.markRead(scan.id);
          }),
        )),
      ]),
    );
  }
}

class _RoomPill extends StatelessWidget {
  const _RoomPill({required this.emoji, required this.label, required this.color});
  final String emoji; final String label; final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withOpacity(0.06),
        border: Border.all(color: color.withOpacity(0.1))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _HowCard extends StatelessWidget {
  const _HowCard({required this.icon, required this.color, required this.title, required this.desc});
  final IconData icon; final Color color; final String title; final String desc;
  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color.withOpacity(0.08)),
          child: Icon(icon, size: 18, color: color)),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
        const SizedBox(height: 2),
        Text(desc, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, height: 1.3)),
      ]),
    ));
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.scan, required this.onTap});
  final LocalScan scan; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final isNew = !scan.isRead && scan.status == ScanStatus.completed;
    final analyzing = scan.status == ScanStatus.analyzing;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isNew ? const Color(0xFF6C5CE7).withOpacity(0.03) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isNew ? const Color(0xFF6C5CE7).withOpacity(0.15) : const Color(0xFFEEF2F7))),
        child: Row(children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0xFFF1F5F9)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: scan.imageBytes.isNotEmpty
                ? Image.memory(scan.imageBytes, fit: BoxFit.cover)
                : const Icon(Icons.home_rounded, color: Color(0xFFCBD5E1), size: 24))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (isNew) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF6C5CE7))),
              Expanded(child: Text(
                scan.analysis?.detectedStyle ?? (analyzing ? 'Analiz ediliyor...' : 'Hata'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isNew ? FontWeight.w700 : FontWeight.w600,
                  color: analyzing ? Colors.grey.shade400 : const Color(0xFF1E293B),
                  fontStyle: analyzing ? FontStyle.italic : FontStyle.normal),
                overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(_ago(scan.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]),
            const SizedBox(height: 4),
            if (scan.analysis != null)
              Text(scan.analysis!.summary, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.4))
            else if (analyzing)
              Row(children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: const Color(0xFF6C5CE7).withOpacity(0.5))),
                const SizedBox(width: 8),
                Text('Koala analiz ediyor...', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              ]),
          ])),
          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300, size: 20),
        ]),
      ),
    );
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'simdi';
    if (d.inMinutes < 60) return '${d.inMinutes} dk';
    if (d.inHours < 24) return '${d.inHours} sa';
    return '${d.inDays}g';
  }
}
"""

with open('lib/views/scan_home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('Done - scan_home_screen.dart')
