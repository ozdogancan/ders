import 'package:flutter/material.dart';
import '../services/credit_service.dart';

class CreditStoreScreen extends StatefulWidget {
  const CreditStoreScreen({super.key});
  @override
  State<CreditStoreScreen> createState() => _CreditStoreScreenState();
}

class _CreditStoreScreenState extends State<CreditStoreScreen> {
  final CreditService _creditService = CreditService();
  int _credits = 0;
  bool _loading = true;
  bool _buying = false;

  static const List<_CreditPackage> _packages = [
    _CreditPackage(
      id: 'koala_10',
      credits: 10,
      bonus: 0,
      price: 29.99,
      label: 'Başlangıç',
      icon: Icons.bolt_rounded,
      colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
    ),
    _CreditPackage(
      id: 'koala_30',
      credits: 30,
      bonus: 5,
      price: 79.99,
      label: 'Popüler',
      icon: Icons.star_rounded,
      colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
      isPopular: true,
    ),
    _CreditPackage(
      id: 'koala_100',
      credits: 100,
      bonus: 20,
      price: 199.99,
      label: 'En Değerli',
      icon: Icons.workspace_premium_rounded,
      colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    final credits = await _creditService.getCredits();
    if (mounted) setState(() { _credits = credits; _loading = false; });
  }

  Future<void> _buyPackage(_CreditPackage pkg) async {
    // Show confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: pkg.colors),
              borderRadius: BorderRadius.circular(18)),
            child: Icon(pkg.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text('${pkg.totalCredits} Kredi',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
          if (pkg.bonus > 0)
            Text('+${pkg.bonus} bonus dahil',
              style: const TextStyle(fontSize: 13, color: Color(0xFF22C55E), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('₺${pkg.price.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF6366F1))),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Satın Al', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ]),
      ),
    );

    if (confirm != true) return;

    setState(() => _buying = true);

    // TODO: RevenueCat / Stripe entegrasyonu buraya gelecek
    // Şimdilik direkt kredi ekliyoruz (test amaçlı)
    final updated = await _creditService.addCredits(pkg.totalCredits);

    if (mounted) {
      setState(() { _credits = updated; _buying = false; });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF22C55E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text('${pkg.totalCredits} kredi eklendi!',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
            : CustomScrollView(slivers: [
                // Header
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(width: 36, height: 36,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFFF1F5F9)),
                        child: const Icon(Icons.arrow_back_rounded, size: 18, color: Color(0xFF475569)))),
                    const SizedBox(width: 14),
                    const Text('Kredi Mağazası',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  ]))),

                // Current balance
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF6366F1), Color(0xFF7C3AED), Color(0xFFA855F7)]),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withAlpha(40), blurRadius: 24, offset: const Offset(0, 8))]),
                    child: Column(children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white.withAlpha(25),
                          border: Border.all(color: Colors.white.withAlpha(40))),
                        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 14),
                      Text('$_credits',
                        style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                      const SizedBox(height: 4),
                      Text('Mevcut Kredin',
                        style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(190), fontWeight: FontWeight.w600)),
                    ]),
                  ),
                )),

                // Section header
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Kredi Paketleri',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    Text('Her mesaj ve soru çözümü 1 kredi harcar',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  ]))),

                // Packages
                SliverList(delegate: SliverChildBuilderDelegate((_, i) {
                  final pkg = _packages[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: _PackageCard(
                      pkg: pkg,
                      buying: _buying,
                      onTap: () => _buyPackage(pkg),
                    ),
                  );
                }, childCount: _packages.length)),

                // Info
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Colors.grey.shade400),
                      const SizedBox(width: 12),
                      Expanded(child: Text(
                        'Krediler hesabına anında eklenir. Soru çözme, chat mesajı ve koç modunda kullanılır.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.5))),
                    ]),
                  ),
                )),

                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ]),
      ),
    );
  }
}

class _CreditPackage {
  const _CreditPackage({
    required this.id,
    required this.credits,
    required this.bonus,
    required this.price,
    required this.label,
    required this.icon,
    required this.colors,
    this.isPopular = false,
  });

  final String id;
  final int credits;
  final int bonus;
  final double price;
  final String label;
  final IconData icon;
  final List<Color> colors;
  final bool isPopular;

  int get totalCredits => credits + bonus;
  double get perCredit => price / totalCredits;
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.pkg, required this.buying, required this.onTap});
  final _CreditPackage pkg;
  final bool buying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: buying ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: pkg.isPopular ? pkg.colors[0].withAlpha(40) : const Color(0xFFEEF2F7)),
          boxShadow: pkg.isPopular
              ? [BoxShadow(color: pkg.colors[0].withAlpha(15), blurRadius: 20, offset: const Offset(0, 6))]
              : [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          // Icon
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: pkg.colors)),
            child: Icon(pkg.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${pkg.credits} Kredi',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              if (pkg.bonus > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withAlpha(12),
                    borderRadius: BorderRadius.circular(8)),
                  child: Text('+${pkg.bonus} bonus',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
                ),
              ],
              if (pkg.isPopular) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: pkg.colors),
                    borderRadius: BorderRadius.circular(8)),
                  child: const Text('Popüler',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text('₺${pkg.perCredit.toStringAsFixed(2)} / kredi',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          ])),

          // Price button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: pkg.colors),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: pkg.colors[0].withAlpha(30), blurRadius: 8, offset: const Offset(0, 3))]),
            child: Text('₺${pkg.price.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}
