import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/koala_tokens.dart';
import '../services/saved_plans_service.dart';
import '../widgets/koala_widgets.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
      case 'style_analysis': return LucideIcons.sparkles;
      case 'color_palette': return LucideIcons.palette;
      case 'product_grid': return LucideIcons.shoppingBag;
      case 'budget_plan': return LucideIcons.wallet;
      case 'designer_card': return LucideIcons.user;
      default: return LucideIcons.bookmark;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'style_analysis': return KoalaColors.accentDeep;
      case 'color_palette': return KoalaColors.pink;
      case 'product_grid': return KoalaColors.blue;
      case 'budget_plan': return KoalaColors.greenAlt;
      case 'designer_card': return KoalaColors.star;
      default: return KoalaColors.accentDeep;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0.5,
        leading: IconButton(icon: Icon(LucideIcons.arrowLeft, color: KoalaColors.ink),
          onPressed: () => Navigator.pop(context)),
        title: Text('Kaydedilen Planlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: KoalaColors.ink)),
      ),
      body: _loading
        ? const LoadingState()
        : _plans.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.bookmark, size: 48, color: Colors.grey.shade300),
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
                    child: const Icon(LucideIcons.trash2, color: Colors.red)),
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
                        Text(plan.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KoalaColors.ink),
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
                            backgroundColor: KoalaColors.accentDeep,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: const Text('Panoya kopyalandı ✨', style: TextStyle(color: Colors.white))));
                        },
                        child: Container(width: 36, height: 36,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: KoalaColors.accentSoft),
                          child: Icon(LucideIcons.share2, size: 16, color: KoalaColors.accentDeep))),
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
