import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/koala_ds.dart';
import '../core/theme/koala_tokens.dart';
import '../services/saved_items_service.dart';
import '../services/taste_profile_service.dart';
import 'free_consult_sheet.dart';

/// Her 10 beğenide swipe ekranında gösterilen "tarz özeti" alt-popup'ı.
///
/// Tüm veri LOKAL: `TasteProfileService.computeProfile()` (SharedPreferences,
/// ağ yok) + bellekteki deck. AI çağrısı / runtime image-gen YOK — maliyet
/// kuralına uygun.
class TasteSummarySheet extends ConsumerWidget {
  const TasteSummarySheet({
    super.key,
    required this.profile,
    required this.topStyleKey,
    required this.palette,
    this.recCard,
  });

  final TasteProfile profile;
  final String topStyleKey;
  final List<String> palette;

  /// {id, title, imageUrl, designerId, category} — null olabilir.
  final Map<String, String>? recCard;

  static Future<void> show(
    BuildContext context, {
    required TasteProfile profile,
    required String topStyleKey,
    required List<String> palette,
    Map<String, String>? recCard,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaDS.surface,
      barrierColor: KoalaDS.ink.withValues(alpha: 0.54),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KoalaR.xl)),
      ),
      builder: (_) => TasteSummarySheet(
        profile: profile,
        topStyleKey: topStyleKey,
        palette: palette,
        recCard: recCard,
      ),
    );
  }

  // ─── Stil adı + renk paleti (deterministik, veri bağımlılığı yok) ───
  static const Map<String, String> _styleNames = {
    'modern': 'Modern',
    'minimalist': 'Minimalist',
    'iskandinav': 'İskandinav',
    'klasik': 'Klasik',
    'endüstriyel': 'Endüstriyel',
    'boho': 'Boho',
    'rustik': 'Rustik',
    'japandi': 'Japandi',
    'mid_century': 'Mid-Century',
    'mediterranean': 'Akdeniz',
  };

  static String prettyStyle(String k) {
    final n = _styleNames[k];
    if (n != null) return n;
    if (k.isEmpty) return 'Tarz';
    return k[0].toUpperCase() + k.substring(1);
  }

  static const Map<String, List<String>> _palettes = {
    'modern': ['#2B2B2B', '#FFFFFF', '#BFBFBF', '#7A7A7A'],
    'minimalist': ['#FFFFFF', '#ECE8E0', '#CFC8B8', '#3A3A3A'],
    'iskandinav': ['#F4EFE7', '#D8C3A5', '#FFFFFF', '#A89B86'],
    'klasik': ['#3E2C20', '#C9A24B', '#F2E8D5', '#7A5C3E'],
    'endüstriyel': ['#3A3A3A', '#8B5E3C', '#C4C4C4', '#1F1F1F'],
    'boho': ['#C57B57', '#E0A96D', '#7A8450', '#F2E2CE'],
    'rustik': ['#6B4A2F', '#A9885F', '#E6D8C3', '#3F2E1E'],
    'japandi': ['#E8E2D6', '#A89B8C', '#3C3A35', '#CBBFA8'],
    'mid_century': ['#D9772B', '#2E4A3F', '#E8D7B0', '#3A2E26'],
    'mediterranean': ['#1E6F8E', '#F2EBDD', '#E0C068', '#3A6B5C'],
  };

  static List<String> paletteFor(String styleKey) =>
      _palettes[styleKey] ??
      const ['#7C6EF2', '#F3F0FF', '#D8D2F5', '#3A3A3A'];

  static Color _hex(String raw) {
    try {
      var s = raw.trim().replaceFirst('#', '');
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return KoalaDS.surfaceMuted;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rc = recCard;
    final hasRec = rc != null && (rc['imageUrl'] ?? '').isNotEmpty;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaDS.line,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Tarzın şekilleniyor ✨', style: KoalaText.h2),
              const SizedBox(height: 4),
              Text(
                '${profile.sampleCount} tasarım beğendin — işte tercihlerin',
                style: KoalaText.bodySec,
              ),
              const SizedBox(height: 20),
              for (final s in profile.topStyles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: _StyleBar(
                    label: prettyStyle(s.style),
                    share: s.share,
                  ),
                ),
              if (profile.isExploring)
                Text(
                  'Henüz birkaç tarz arasında geziniyorsun — keşfetmeye devam!',
                  style: KoalaText.bodySmall,
                ),
              const SizedBox(height: 16),
              Text('Tarzının renkleri', style: KoalaText.h4),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final h in palette.take(5))
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _hex(h),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: KoalaDS.line, width: 0.5),
                          boxShadow: KoalaElev.card,
                        ),
                      ),
                    ),
                ],
              ),
              if (hasRec) ...[
                const SizedBox(height: 22),
                Text('Sana özel öneri', style: KoalaText.h4),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Image.network(
                      rc['imageUrl']!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(color: KoalaDS.surfaceMuted),
                    ),
                  ),
                ),
                if ((rc['title'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      rc['title']!,
                      style: KoalaText.h4,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (!hasRec || (rc['id'] ?? '').isEmpty)
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          SavedItemsService.saveItem(
                            type: SavedItemType.design,
                            itemId: rc['id']!,
                            title: rc['title'] ?? '',
                            imageUrl: rc['imageUrl'] ?? '',
                            subtitle: rc['category'] ?? '',
                            extraData: const {'source': 'taste_summary'},
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Tasarım kaydedildi')),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: KoalaDS.accentDeep,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Bu tasarımı kaydet'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SecondaryBtn(
                      label: "Koala AI'ya sor",
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/chat/ai', extra: {
                          'initialText':
                              'Tarzım ${prettyStyle(topStyleKey)}. Bu tarza '
                              'uygun, evime dair önerilerin var mı?',
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SecondaryBtn(
                      label: 'Evlumba Design',
                      onTap: () {
                        Navigator.of(context).pop();
                        // Tek-konuşma + free-consult gate.
                        String? projectTitle;
                        Map<String, dynamic>? pendingDesign;
                        if (hasRec && (rc['id'] ?? '').isNotEmpty) {
                          projectTitle = (rc['title'] ?? '').isNotEmpty
                              ? rc['title']
                              : 'Tasarım';
                          pendingDesign = {
                            'id': rc['id'],
                            'title': (rc['title'] ?? '').isNotEmpty
                                ? rc['title']
                                : 'Tasarım',
                            'imageUrl': rc['imageUrl'] ?? '',
                            if ((rc['category'] ?? '').isNotEmpty)
                              'category': rc['category'],
                            'designerId': 'evlumba-design',
                          };
                        }
                        enterEvlumbaConversation(
                          context,
                          ref,
                          projectTitle: projectTitle,
                          pendingDesign: pendingDesign,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Keşfetmeye devam', style: KoalaText.bodySec),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleBar extends StatelessWidget {
  const _StyleBar({required this.label, required this.share});

  final String label;
  final double share;

  @override
  Widget build(BuildContext context) {
    final pct = (share * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: KoalaText.h4),
            Text('%$pct', style: KoalaText.bodySec),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: share.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: KoalaDS.accentTint,
            valueColor:
                const AlwaysStoppedAnimation<Color>(KoalaDS.accentDeep),
          ),
        ),
      ],
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  const _SecondaryBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: KoalaDS.accentDeep,
        side: const BorderSide(color: KoalaDS.line),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
