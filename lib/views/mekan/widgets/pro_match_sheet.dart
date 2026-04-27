import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../services/analytics_service.dart';
import '../../../services/messaging_service.dart';
import '../../conversation_detail_screen.dart';

/// Pro Marketplace — restyle sonrası "Bu tasarımı gerçeğe dönüştür" basılınca
/// açılan modal. AI'nın oluşturduğu görsele en uygun iç mimarları getirir
/// (`/api/match-designers`) ve kullanıcıya tek bir net aksiyon sunar: "Mesaj at".
///
/// Tasarım niyeti: SnapHome benzeri tanıdık marketplace dili, Koala sıcak-krem
/// estetiği. Editorial başlık (Fraunces), KoalaText.bodySec body. Dört state:
/// loading / loaded / empty / error — her biri sade ve anlaşılır.
class ProMatchSheet extends StatefulWidget {
  /// Restyle çıktısı görseli — https URL veya data URL olabilir. Hem
  /// `/api/match-designers` body'sine, hem de "Mesaj at" akışında
  /// attachment_url olarak ilk mesaja iliştirilir.
  final String restyleUrl;

  /// Türkçe oda etiketi — match endpoint Turkish label bekliyor:
  /// "Yatak Odası" | "Oturma Odası" | "Banyo" | "Mutfak" | "Antre" | "Konut".
  final String roomType;

  /// Tema/stil — örn. "minimalist". Lowercase, ThemeOption.value ile aynı.
  final String theme;

  /// İleride profile/geoloc'tan gelecek; şimdilik null.
  final String? city;

  const ProMatchSheet({
    super.key,
    required this.restyleUrl,
    required this.roomType,
    required this.theme,
    this.city,
  });

  static Future<void> show(
    BuildContext context, {
    required String restyleUrl,
    required String roomType,
    required String theme,
    String? city,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => ProMatchSheet(
        restyleUrl: restyleUrl,
        roomType: roomType,
        theme: theme,
        city: city,
      ),
    );
  }

  @override
  State<ProMatchSheet> createState() => _ProMatchSheetState();
}

class _ProMatchSheetState extends State<ProMatchSheet> {
  late Future<_MatchResponse> _future;

  @override
  void initState() {
    super.initState();
    unawaited(
      Analytics.log('pro_match_opened', {
        'room_type': widget.roomType,
        'theme': widget.theme,
      }),
    );
    _future = _loadMatches();
  }

  Future<_MatchResponse> _loadMatches() async {
    final apiUrl = Env.koalaApiUrl;
    final res = await http
        .post(
          Uri.parse('$apiUrl/api/match-designers'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'image': widget.restyleUrl,
            'room_type': widget.roomType,
            'theme': widget.theme,
            if (widget.city != null) 'city': widget.city,
            'match_count': 8,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final parsed = _MatchResponse.fromJson(body);
    unawaited(
      Analytics.log('pro_match_loaded', {
        'match_count': parsed.matches.length,
        'latency_ms': parsed.latencyMs,
        'has_results': parsed.matches.isNotEmpty,
        'theme': widget.theme,
        'room_type': widget.roomType,
      }),
    );
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KoalaRadius.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: KoalaSpacing.md),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.borderMed,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                ),
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tasarımına en uygun mimarlar',
                    style: KoalaText.serif(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ).animate(delay: 80.ms).fadeIn(duration: 280.ms).slideY(
                        begin: 0.06,
                        end: 0,
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: KoalaSpacing.xs),
                  Text(
                    'Görseline benzer projeler yapan iç mimarlar — '
                    'birine mesaj at, sohbet başlasın.',
                    style: KoalaText.bodySec,
                  ).animate(delay: 120.ms).fadeIn(duration: 320.ms),
                ],
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            // Body
            Flexible(
              child: FutureBuilder<_MatchResponse>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const _LoadingState();
                  }
                  if (snap.hasError) {
                    return _ErrorState(onRetry: () {
                      setState(() => _future = _loadMatches());
                    });
                  }
                  final data = snap.data!;
                  if (data.matches.isEmpty) {
                    return const _EmptyState();
                  }
                  return _MatchList(
                    matches: data.matches,
                    onMessage: _openMessageFlow,
                    onTapCard: _openProfileSheet,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProfileSheet(_DesignerMatch match) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _DesignerProfileSheet(
        match: match,
        onMessage: () {
          Navigator.of(context).pop();
          _openMessageFlow(match);
        },
      ),
    );
  }

  void _openMessageFlow(_DesignerMatch match) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _MessageDraftSheet(
        match: match,
        roomType: widget.roomType,
        restyleUrl: widget.restyleUrl,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATES
// ═══════════════════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.lg,
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
      ),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: KoalaSpacing.lg),
        itemBuilder: (_, _) => _SkeletonCard()
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fadeIn(duration: 600.ms, begin: 0.55),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(color: KoalaColors.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(color: KoalaColors.surfaceAlt),
          ),
          Padding(
            padding: const EdgeInsets.all(KoalaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140,
                  height: 14,
                  color: KoalaColors.surfaceAlt,
                ),
                const SizedBox(height: KoalaSpacing.sm),
                Container(
                  width: 200,
                  height: 12,
                  color: KoalaColors.surfaceAlt,
                ),
                const SizedBox(height: KoalaSpacing.lg),
                Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    color: KoalaColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: KoalaColors.accentSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(LucideIcons.search,
                color: KoalaColors.accentDeep, size: 26),
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Text(
            'Şu an bu tarza tam uyan birini bulamadık',
            style: KoalaText.serif(fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.sm),
          const Text(
            'Veritabanımız büyüyor. Biraz sonra tekrar dener misin?',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: KoalaColors.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(LucideIcons.cloudOff,
                color: KoalaColors.error, size: 26),
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Text(
            'Mimarları getiremedik',
            style: KoalaText.serif(fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.sm),
          const Text(
            'İnternet bağlantını kontrol edip tekrar dener misin?',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.lg),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: KoalaColors.accentDeep,
              foregroundColor: Colors.white,
              minimumSize: const Size(180, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KoalaRadius.md),
              ),
              textStyle: KoalaText.button,
            ),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MATCH LIST + CARD
// ═══════════════════════════════════════════════════════════════════════════

class _MatchList extends StatelessWidget {
  final List<_DesignerMatch> matches;
  final void Function(_DesignerMatch) onMessage;
  final void Function(_DesignerMatch) onTapCard;

  const _MatchList({
    required this.matches,
    required this.onMessage,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        0,
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
      ),
      itemCount: matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: KoalaSpacing.lg),
      itemBuilder: (ctx, i) {
        final m = matches[i];
        return _MatchCard(
          match: m,
          position: i,
          onTap: () => onTapCard(m),
          onMessage: () => onMessage(m),
        ).animate(delay: (220 + i * 60).ms).fadeIn(duration: 280.ms).slideY(
              begin: 0.06,
              end: 0,
              duration: 320.ms,
              curve: Curves.easeOutCubic,
            );
      },
    );
  }
}

class _MatchCard extends StatefulWidget {
  final _DesignerMatch match;
  final int position;
  final VoidCallback onTap;
  final VoidCallback onMessage;

  const _MatchCard({
    required this.match,
    required this.position,
    required this.onTap,
    required this.onMessage,
  });

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  @override
  void initState() {
    super.initState();
    // İlk render = "viewed" — VisibilityDetector aşırı (skeleton zaten viewport
    // içindeydi). List 8-10 öğeyle sınırlı, simple log yeterli.
    unawaited(
      Analytics.log('pro_match_card_viewed', {
        'designer_id': widget.match.designer.id,
        'similarity': widget.match.similarity,
        'position': widget.position,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final designer = m.designer;
    final project = m.project;

    return Material(
      color: KoalaColors.surface,
      borderRadius: BorderRadius.circular(KoalaRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: KoalaColors.border, width: 0.5),
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top: project cover with similarity badge
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: project.coverUrl.isNotEmpty
                        ? Image.network(
                            project.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: KoalaColors.surfaceAlt,
                              alignment: Alignment.center,
                              child: const Icon(LucideIcons.image,
                                  color: KoalaColors.textTer, size: 28),
                            ),
                          )
                        : Container(color: KoalaColors.surfaceAlt),
                  ),
                  Positioned(
                    top: KoalaSpacing.md,
                    right: KoalaSpacing.md,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KoalaSpacing.md,
                        vertical: KoalaSpacing.xs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: KoalaColors.accentSoft,
                        borderRadius: BorderRadius.circular(KoalaRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.sparkles,
                              size: 12, color: KoalaColors.accentDeep),
                          const SizedBox(width: 4),
                          Text(
                            '%${(m.similarity * 100).round()} uyumlu',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: KoalaColors.accentDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // ── Bottom: designer info
              Padding(
                padding: const EdgeInsets.all(KoalaSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar + name + verified
                    Row(
                      children: [
                        _Avatar(url: designer.avatarUrl, size: 36),
                        const SizedBox(width: KoalaSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      designer.name,
                                      style: KoalaText.h3,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (designer.isVerified) ...[
                                    const SizedBox(width: 4),
                                    const Icon(LucideIcons.badgeCheck,
                                        size: 16,
                                        color: KoalaColors.accentDeep),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _subtitleFor(designer),
                                style: KoalaText.bodySec,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (designer.rating != null) ...[
                          const SizedBox(width: KoalaSpacing.sm),
                          _RatingPill(
                            rating: designer.rating!,
                            count: designer.reviewCount,
                          ),
                        ],
                      ],
                    ),
                    // Tags + colors
                    if (project.tags.isNotEmpty ||
                        (project.colorPalette?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: KoalaSpacing.md),
                      Row(
                        children: [
                          if (project.tags.isNotEmpty)
                            Expanded(
                              child: Wrap(
                                spacing: KoalaSpacing.xs + 2,
                                runSpacing: KoalaSpacing.xs,
                                children: project.tags
                                    .take(3)
                                    .map((t) => _TagChip(label: t))
                                    .toList(),
                              ),
                            ),
                          if (project.colorPalette != null &&
                              project.colorPalette!.isNotEmpty) ...[
                            const SizedBox(width: KoalaSpacing.sm),
                            _ColorDots(hexes: project.colorPalette!),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: KoalaSpacing.md),
                    // Price + response time
                    Row(
                      children: [
                        if (designer.startingFrom != null) ...[
                          const Icon(LucideIcons.tag,
                              size: 14, color: KoalaColors.textMed),
                          const SizedBox(width: 4),
                          Text(
                            '₺${_fmt(designer.startingFrom!)}\'den başlıyor',
                            style: KoalaText.label
                                .copyWith(color: KoalaColors.textMed),
                          ),
                          const SizedBox(width: KoalaSpacing.md),
                        ],
                        if (designer.responseTime != null &&
                            designer.responseTime!.isNotEmpty) ...[
                          const Icon(LucideIcons.clock,
                              size: 14, color: KoalaColors.textMed),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              designer.responseTime!,
                              style: KoalaText.label
                                  .copyWith(color: KoalaColors.textMed),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: KoalaSpacing.lg),
                    // CTA
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.onMessage,
                        style: FilledButton.styleFrom(
                          backgroundColor: KoalaColors.accentDeep,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(KoalaRadius.md),
                          ),
                          textStyle: KoalaText.button,
                        ),
                        icon: const Icon(LucideIcons.messageCircle, size: 16),
                        label: const Text('Mesaj at'),
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

  String _subtitleFor(_Designer d) {
    final parts = <String>[];
    if (d.specialty != null && d.specialty!.isNotEmpty) parts.add(d.specialty!);
    if (d.city != null && d.city!.isNotEmpty) parts.add(d.city!);
    return parts.isEmpty ? 'İç mimar' : parts.join(' · ');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _DesignerProfileSheet extends StatelessWidget {
  final _DesignerMatch match;
  final VoidCallback onMessage;

  const _DesignerProfileSheet({
    required this.match,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.92;
    final d = match.designer;
    final p = match.project;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KoalaRadius.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: KoalaSpacing.md),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.borderMed,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  KoalaSpacing.lg,
                  0,
                  KoalaSpacing.xxl,
                ),
                children: [
                  // Hero project image
                  if (p.coverUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: KoalaSpacing.xl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(KoalaRadius.lg),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            p.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Container(color: KoalaColors.surfaceAlt),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: KoalaSpacing.lg),
                  // Designer header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KoalaSpacing.xl),
                    child: Row(
                      children: [
                        _Avatar(url: d.avatarUrl, size: 56),
                        const SizedBox(width: KoalaSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      d.name,
                                      style: KoalaText.serif(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (d.isVerified) ...[
                                    const SizedBox(width: 6),
                                    const Icon(LucideIcons.badgeCheck,
                                        size: 18,
                                        color: KoalaColors.accentDeep),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (d.specialty != null &&
                                      d.specialty!.isNotEmpty)
                                    d.specialty!,
                                  if (d.city != null && d.city!.isNotEmpty)
                                    d.city!,
                                ].join(' · '),
                                style: KoalaText.bodySec,
                              ),
                              if (d.rating != null) ...[
                                const SizedBox(height: KoalaSpacing.xs),
                                _RatingPill(
                                  rating: d.rating!,
                                  count: d.reviewCount,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Project meta
                  if (p.title.isNotEmpty) ...[
                    const SizedBox(height: KoalaSpacing.xl),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: KoalaSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bu proje',
                              style: KoalaText.caption,
                              textAlign: TextAlign.left),
                          const SizedBox(height: KoalaSpacing.xs),
                          Text(p.title,
                              style: KoalaText.h3, textAlign: TextAlign.left),
                          if (p.location != null && p.location!.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: KoalaSpacing.xs),
                              child: Text(p.location!,
                                  style: KoalaText.bodySec),
                            ),
                        ],
                      ),
                    ),
                  ],
                  // Related projects horizontal scroll
                  if (match.relatedProjects.isNotEmpty) ...[
                    const SizedBox(height: KoalaSpacing.xl),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
                      child: Text('Diğer projeleri', style: KoalaText.h4),
                    ),
                    const SizedBox(height: KoalaSpacing.md),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: KoalaSpacing.xl),
                        itemCount: match.relatedProjects.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: KoalaSpacing.md),
                        itemBuilder: (_, i) {
                          final r = match.relatedProjects[i];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(KoalaRadius.md),
                            child: SizedBox(
                              width: 160,
                              child: Image.network(
                                r.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: KoalaColors.surfaceAlt,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  // Instagram
                  if (d.instagram != null && d.instagram!.isNotEmpty) ...[
                    const SizedBox(height: KoalaSpacing.xl),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: KoalaSpacing.xl),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.instagram,
                              size: 16, color: KoalaColors.textMed),
                          const SizedBox(width: KoalaSpacing.sm),
                          Text('@${d.instagram}',
                              style: KoalaText.label
                                  .copyWith(color: KoalaColors.textMed)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Bottom CTA bar
            Container(
              padding: const EdgeInsets.fromLTRB(
                KoalaSpacing.xl,
                KoalaSpacing.md,
                KoalaSpacing.xl,
                KoalaSpacing.lg,
              ),
              decoration: const BoxDecoration(
                color: KoalaColors.surface,
                border: Border(
                  top: BorderSide(color: KoalaColors.border, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (d.startingFrom != null)
                          Text('₺${_fmt(d.startingFrom!)}\'den',
                              style: KoalaText.h4),
                        if (d.responseTime != null &&
                            d.responseTime!.isNotEmpty)
                          Text(d.responseTime!, style: KoalaText.bodySmall),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onMessage,
                    style: FilledButton.styleFrom(
                      backgroundColor: KoalaColors.accentDeep,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(160, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KoalaRadius.md),
                      ),
                      textStyle: KoalaText.button,
                    ),
                    icon: const Icon(LucideIcons.messageCircle, size: 16),
                    label: const Text('Mesaj at'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGE DRAFT SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _MessageDraftSheet extends StatefulWidget {
  final _DesignerMatch match;
  final String roomType;
  final String restyleUrl;

  const _MessageDraftSheet({
    required this.match,
    required this.roomType,
    required this.restyleUrl,
  });

  @override
  State<_MessageDraftSheet> createState() => _MessageDraftSheetState();
}

class _MessageDraftSheetState extends State<_MessageDraftSheet> {
  late final TextEditingController _ctrl;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _initialDraft());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _initialDraft() {
    final phrase = _roomPhrase(widget.roomType);
    return 'Merhaba ${widget.match.designer.name},\n\n'
        '$phrase yaptığınız tasarımları çok beğendim. AI ile hazırladığım bir '
        'görselim var — bu tarzda gerçek bir tasarım için sizinle çalışmak '
        'istiyorum. Müsait olduğunuzda görüşelim.';
  }

  String _roomPhrase(String roomType) {
    final lower = roomType.toLowerCase();
    if (lower.contains('yatak')) return 'Yatak odam için';
    if (lower.contains('oturma') || lower.contains('salon')) {
      return 'Salonum için';
    }
    if (lower.contains('mutfak')) return 'Mutfağım için';
    if (lower.contains('banyo')) return 'Banyom için';
    if (lower.contains('antre')) return 'Antrem için';
    if (lower.contains('yemek')) return 'Yemek odam için';
    return 'Mekanım için';
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final designer = widget.match.designer;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final conv = await MessagingService.getOrCreateConversation(
        designerId: designer.id,
        contextType: 'mekan_pro_match',
        contextTitle: 'Koala mekan tasarımı',
      );
      if (conv == null) {
        throw StateError(
            MessagingService.lastConvError ?? 'Sohbet başlatılamadı');
      }
      final convId = conv['id']?.toString();
      if (convId == null || convId.isEmpty) {
        throw StateError('Sohbet kimliği alınamadı');
      }

      final msg = await MessagingService.sendMessage(
        conversationId: convId,
        content: _ctrl.text.trim(),
        type: MessageType.image,
        attachmentUrl: widget.restyleUrl,
      );
      if (msg == null) {
        throw StateError(
            MessagingService.lastSendError ?? 'Mesaj gönderilemedi');
      }

      unawaited(
        Analytics.log('pro_match_message_sent', {
          'designer_id': designer.id,
          'similarity': widget.match.similarity,
          'room_type': widget.roomType,
        }),
      );
      unawaited(Analytics.designerMessageSent(convId));

      if (!mounted) return;
      navigator.pop(); // close draft sheet
      navigator.pop(); // close match sheet
      messenger.showSnackBar(
        SnackBar(
          content: Text('Mesajın iletildi · ${designer.name}'),
          backgroundColor: KoalaColors.greenBright,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Navigate to chat detail
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ConversationDetailScreen(
            conversationId: convId,
            designerId: designer.id,
            designerName: designer.name,
            designerAvatarUrl: designer.avatarUrl,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Mesaj gönderilemedi: $e'),
          backgroundColor: KoalaColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final designer = widget.match.designer;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: const BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KoalaRadius.xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl,
          KoalaSpacing.md,
          KoalaSpacing.xl,
          KoalaSpacing.xl,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.borderMed,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: KoalaSpacing.lg),
              Row(
                children: [
                  _Avatar(url: designer.avatarUrl, size: 40),
                  const SizedBox(width: KoalaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(designer.name, style: KoalaText.h3),
                        Text('Mesajını gözden geçir',
                            style: KoalaText.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KoalaSpacing.lg),
              // Attached design preview
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(KoalaRadius.sm),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Image.network(
                        widget.restyleUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: KoalaColors.surfaceAlt,
                          child: const Icon(LucideIcons.image,
                              size: 20, color: KoalaColors.textTer),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: KoalaSpacing.md),
                  Expanded(
                    child: Text(
                      'AI tasarımın mesaja eklenecek',
                      style: KoalaText.bodySec,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KoalaSpacing.lg),
              TextField(
                controller: _ctrl,
                maxLines: 6,
                minLines: 4,
                style: KoalaText.body,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: KoalaColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
                    borderSide:
                        const BorderSide(color: KoalaColors.borderSolid),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
                    borderSide:
                        const BorderSide(color: KoalaColors.borderSolid),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
                    borderSide:
                        const BorderSide(color: KoalaColors.accentDeep),
                  ),
                  contentPadding: const EdgeInsets.all(KoalaSpacing.md),
                ),
              ),
              const SizedBox(height: KoalaSpacing.lg),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
                  ),
                  textStyle: KoalaText.button,
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(LucideIcons.send, size: 16),
                label: Text(_sending ? 'Gönderiliyor…' : 'Mesajı gönder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED ATOMS
// ═══════════════════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final String? url;
  final double size;

  const _Avatar({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: KoalaColors.surfaceAlt,
        shape: BoxShape.circle,
        border: Border.all(color: KoalaColors.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(LucideIcons.user,
                  color: KoalaColors.textTer, size: 18),
            )
          : const Icon(LucideIcons.user,
              color: KoalaColors.textTer, size: 18),
    );
  }
}

class _RatingPill extends StatelessWidget {
  final double rating;
  final int count;
  const _RatingPill({required this.rating, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.star,
            size: 13, color: KoalaColors.star),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: KoalaColors.text,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 3),
          Text(
            '($count)',
            style: KoalaText.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoalaSpacing.sm + 2,
        vertical: KoalaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: KoalaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: KoalaColors.textMed,
        ),
      ),
    );
  }
}

class _ColorDots extends StatelessWidget {
  final List<String> hexes;
  const _ColorDots({required this.hexes});

  @override
  Widget build(BuildContext context) {
    final dots = hexes.take(4).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < dots.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _parseHex(dots[i]),
                shape: BoxShape.circle,
                border: Border.all(color: KoalaColors.border, width: 0.5),
              ),
            ),
          ),
      ],
    );
  }

  Color _parseHex(String raw) {
    try {
      var s = raw.trim().replaceFirst('#', '');
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return KoalaColors.surfaceAlt;
    }
  }
}

String _fmt(num n) {
  final s = n.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final fromRight = s.length - i;
    buf.write(s[i]);
    if (fromRight > 1 && fromRight % 3 == 1) buf.write('.');
  }
  return buf.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
// DTOs — match-designers response (keep local; not reused elsewhere yet)
// ═══════════════════════════════════════════════════════════════════════════

class _MatchResponse {
  final List<_DesignerMatch> matches;
  final int total;
  final int latencyMs;

  const _MatchResponse({
    required this.matches,
    required this.total,
    required this.latencyMs,
  });

  factory _MatchResponse.fromJson(Map<String, dynamic> j) {
    final raw = (j['matches'] as List?) ?? const [];
    return _MatchResponse(
      matches: raw
          .whereType<Map<String, dynamic>>()
          .map(_DesignerMatch.fromJson)
          .toList(),
      total: (j['total'] as num?)?.toInt() ?? 0,
      latencyMs: (j['latency_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class _DesignerMatch {
  final double similarity;
  final _Designer designer;
  final _Project project;
  final List<_RelatedProject> relatedProjects;

  const _DesignerMatch({
    required this.similarity,
    required this.designer,
    required this.project,
    required this.relatedProjects,
  });

  factory _DesignerMatch.fromJson(Map<String, dynamic> j) {
    return _DesignerMatch(
      similarity: (j['similarity'] as num?)?.toDouble() ?? 0,
      designer: _Designer.fromJson(
          (j['designer'] as Map?)?.cast<String, dynamic>() ?? const {}),
      project: _Project.fromJson(
          (j['project'] as Map?)?.cast<String, dynamic>() ?? const {}),
      relatedProjects: ((j['related_projects'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_RelatedProject.fromJson)
          .toList(),
    );
  }
}

class _Designer {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? city;
  final String? specialty;
  final String? slug;
  final double? rating;
  final int reviewCount;
  final String? responseTime;
  final num? startingFrom;
  final bool isVerified;
  final String? instagram;

  const _Designer({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.city,
    required this.specialty,
    required this.slug,
    required this.rating,
    required this.reviewCount,
    required this.responseTime,
    required this.startingFrom,
    required this.isVerified,
    required this.instagram,
  });

  factory _Designer.fromJson(Map<String, dynamic> j) => _Designer(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'İsimsiz',
        avatarUrl: j['avatar_url']?.toString(),
        city: j['city']?.toString(),
        specialty: j['specialty']?.toString(),
        slug: j['slug']?.toString(),
        rating: (j['rating'] as num?)?.toDouble(),
        reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
        responseTime: j['response_time']?.toString(),
        startingFrom: j['starting_from'] as num?,
        isVerified: j['is_verified'] == true,
        instagram: j['instagram']?.toString(),
      );
}

class _Project {
  final String id;
  final String title;
  final String? type;
  final String? location;
  final String coverUrl;
  final List<String> galleryUrls;
  final List<String> tags;
  final List<String>? colorPalette;

  const _Project({
    required this.id,
    required this.title,
    required this.type,
    required this.location,
    required this.coverUrl,
    required this.galleryUrls,
    required this.tags,
    required this.colorPalette,
  });

  factory _Project.fromJson(Map<String, dynamic> j) => _Project(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        type: j['type']?.toString(),
        location: j['location']?.toString(),
        coverUrl: j['cover_url']?.toString() ?? '',
        galleryUrls: ((j['gallery_urls'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        tags: ((j['tags'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        colorPalette: j['color_palette'] is List
            ? (j['color_palette'] as List).map((e) => e.toString()).toList()
            : null,
      );
}

class _RelatedProject {
  final String id;
  final String title;
  final String coverUrl;
  final double similarity;

  const _RelatedProject({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.similarity,
  });

  factory _RelatedProject.fromJson(Map<String, dynamic> j) => _RelatedProject(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        coverUrl: j['cover_url']?.toString() ?? '',
        similarity: (j['similarity'] as num?)?.toDouble() ?? 0,
      );
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => 'HTTP $message';
}
