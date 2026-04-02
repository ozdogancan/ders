import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';
import '../services/saved_items_service.dart';

/// Reusable kaydet butonu — kalp/bookmark ikonu.
/// Design, designer veya product kartlarına eklenir.
/// SavedItemsService.toggle() ile kaydet/kaldır yapar.
class SaveButton extends StatefulWidget {
  const SaveButton({
    super.key,
    required this.itemType,
    required this.itemId,
    this.title,
    this.imageUrl,
    this.subtitle,
    this.extraData,
    this.size = 22,
    this.useBookmark = false,
    this.onToggled,
  });

  final SavedItemType itemType;
  final String itemId;
  final String? title;
  final String? imageUrl;
  final String? subtitle;
  final Map<String, dynamic>? extraData;
  final double size;
  final bool useBookmark; // true ise bookmark ikonu, false ise kalp
  final void Function(bool isSaved)? onToggled;

  @override
  State<SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<SaveButton>
    with SingleTickerProviderStateMixin {
  bool _saved = false;
  bool _loading = true;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    ));
    _checkSaved();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkSaved() async {
    final result = await SavedItemsService.isSaved(
      type: widget.itemType,
      itemId: widget.itemId,
    );
    if (mounted) setState(() { _saved = result; _loading = false; });
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);

    final result = await SavedItemsService.toggle(
      type: widget.itemType,
      itemId: widget.itemId,
      title: widget.title,
      imageUrl: widget.imageUrl,
      subtitle: widget.subtitle,
      extraData: widget.extraData,
    );

    if (result && mounted) {
      setState(() {
        _saved = !_saved;
        _loading = false;
      });
      _animController.forward(from: 0);
      widget.onToggled?.call(_saved);
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final IconData filledIcon =
        widget.useBookmark ? Icons.bookmark_rounded : Icons.favorite_rounded;
    final IconData outlinedIcon = widget.useBookmark
        ? Icons.bookmark_border_rounded
        : Icons.favorite_border_rounded;

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: _toggle,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(KoalaSpacing.sm),
          child: _loading
              ? SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KoalaColors.textTer,
                  ),
                )
              : Icon(
                  _saved ? filledIcon : outlinedIcon,
                  size: widget.size,
                  color: _saved ? KoalaColors.error : KoalaColors.textSec,
                ),
        ),
      ),
    );
  }
}
