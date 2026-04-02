import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/saved_plans_service.dart';

class SavedPlansScreen extends StatefulWidget {
  const SavedPlansScreen({super.key});
  @override
  State<SavedPlansScreen> createState() => _SavedPlansScreenState();
}

class _SavedPlansScreenState extends State<SavedPlansScreen> {
  List<SavedPlan> _plans = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final plans = await SavedPlansService.loadAll();
    if (mounted) setState(() { _plans = plans; _loading = false; });
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'style_analysis': return 'Stil Analizi';
      case 'color_palette': return 'Renk Paleti';
      case 'product_grid': return 'Ürün Önerisi';
      case 'budget_plan': return 'Bütçe Planı';
      case 'designer_card': return 'Tasarımcı';
      default: return 'Plan';
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'style_analysis': return Icons.style_rounded;
      case 'color_palette': return Icons.palette_rounded;
      case 'product_grid': return Icons.shopping_bag_rounded;
      case 'budget_plan': return Icons.account_balance_wallet_rounded;
      case 'designer_card': return Icons.person_rounded;
      default: return Icons.bookmark_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'style_analysis': return const Color(0xFF6C5CE7);
      case 'color_palette': return const Color(0xFFEC4899);
      case 'product_grid': return const Color(0xFF3B82F6);
      case 'budget_plan': return const Color(0xFF10B981);
      case 'designer_card': return const Color(0xFFF59E0B);
      default: return const Color(0xFF6C5CE7);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1D2A)),
          onPressed: () => Navigator.pop(context)),
        title: const Text('Kaydedilen Planlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)))
        : _plans.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bookmark_border_rounded, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('Henüz kayıtlı plan yok', style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
              const SizedBox(height: 4),
              Text('Chat\'te kartların altındaki ❤️ butonuna bas', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _plans.length,
              itemBuilder: (_, i) {
                final plan = _plans[i];
                final color = _typeColor(plan.type);
                return Dismissible(
                  key: Key(plan.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.red.shade50),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_rounded, color: Colors.red)),
                  onDismissed: (_) async {
                    await SavedPlansService.remove(plan.id);
                    _load();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16), color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 12, offset: const Offset(0, 3))]),
                    child: Row(children: [
                      Container(width: 44, height: 44,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: color.withValues(alpha:0.1)),
                        child: Icon(_typeIcon(plan.type), size: 20, color: color)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(plan.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(_typeLabel(plan.type), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ])),
                      // Share button
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          final text = _planToText(plan);
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF6C5CE7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: const Text('Panoya kopyalandı ✨', style: TextStyle(color: Colors.white))));
                        },
                        child: Container(width: 36, height: 36,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF3F0FF)),
                          child: const Icon(Icons.share_rounded, size: 16, color: Color(0xFF6C5CE7)))),
                    ])));
              }),
    );
  }

  String _planToText(SavedPlan plan) {
    final buf = StringBuffer('🐨 Koala - ${plan.title}\n\n');
    switch (plan.type) {
      case 'color_palette':
        final colors = (plan.data['colors'] as List?) ?? [];
        for (final c in colors) {
          if (c is Map) buf.writeln('${c['name'] ?? ''}: ${c['hex'] ?? ''}');
        }
      case 'budget_plan':
        buf.writeln('Toplam: ${plan.data['total_budget'] ?? ''}');
        final items = (plan.data['items'] as List?) ?? [];
        for (final i in items) {
          if (i is Map) buf.writeln('• ${i['category']}: ${i['amount']}');
        }
      default:
        buf.writeln(plan.data.toString().substring(0, 200.clamp(0, plan.data.toString().length)));
    }
    buf.writeln('\nevlumba.com ile keşfet');
    return buf.toString();
  }
}
