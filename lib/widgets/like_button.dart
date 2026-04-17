import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../helpers/auth_guard.dart';
import '../services/likes_service.dart';
import '../services/saved_items_service.dart';

/// Beğen butonu — kalp ikonu, basıldığında scale animasyonu + DB toggle.
/// SaveButton'a paralel dizayn: bookmark yerine heart.
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.itemType,
    required this.itemId,
    this.title,
    this.imageUrl,
    this.subtitle,
    this.size = 22,
    this.onToggled,
  });

  final SavedItemType itemType;
  final String itemId;
  final String? title;
  final String? imageUrl;
  final String? subtitle;
  final double size;
  final ValueChanged<bool>? onToggled;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with SingleTickerProviderStateMixin {
  bool _liked = false;
  bool _busy = false;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 60),
  ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final liked = await LikesService.isLiked(
      type: widget.itemType,
      itemId: widget.itemId,
    );
    if (mounted) setState(() => _liked = liked);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    if (!await ensureAuthenticated(context)) return;
    if (!mounted) return;

    final next = !_liked;
    setState(() {
      _liked = next;
      _busy = true;
    });
    if (next) _ctrl.forward(from: 0);

    final ok = await LikesService.toggle(
      type: widget.itemType,
      itemId: widget.itemId,
      title: widget.title,
      imageUrl: widget.imageUrl,
      subtitle: widget.subtitle,
    );

    if (!mounted) return;
    if (!ok) {
      // Revert
      setState(() => _liked = !next);
    } else {
      widget.onToggled?.call(next);
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Filled heart when liked — Material favorite_rounded (solid);
              // outlined state LucideIcons.heart (stroke). İki ayrı ikonu
              // overlay etmek yerine state'e göre birini gösteriyoruz.
              if (_liked)
                Icon(
                  Icons.favorite_rounded,
                  size: widget.size,
                  color: const Color(0xFFEF4444),
                )
              else
                Icon(
                  LucideIcons.heart,
                  size: widget.size,
                  color: KoalaColors.textTer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
