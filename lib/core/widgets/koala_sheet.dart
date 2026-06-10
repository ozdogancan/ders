import 'package:flutter/material.dart';

import '../theme/koala_ds.dart';

/// Tüm bottom-sheet'ler için tek taban. 37 dağınık showModalBottomSheet
/// çağrısı bunu miras alacak: xl28 üst köşe, drag handle, surface, safe-area,
/// slow+spring giriş. İçeriği `builder` döndürür.
///
/// Kullanım:
///   showKoalaSheet(context, builder: (ctx) => MySheetBody());
Future<T?> showKoalaSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showHandle = true,
  EdgeInsets padding = const EdgeInsets.fromLTRB(
      KoalaGap.xl, KoalaGap.sm, KoalaGap.xl, KoalaGap.xl),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: KoalaDS.ink.withValues(alpha: 0.45),
    transitionAnimationController: null,
    builder: (ctx) {
      return AnimatedPadding(
        duration: KoalaMotion.fast,
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: KoalaDS.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(KoalaR.xl)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHandle)
                  Container(
                    margin: const EdgeInsets.only(top: KoalaGap.md, bottom: KoalaGap.xs),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: KoalaDS.line,
                      borderRadius: BorderRadius.circular(KoalaR.pill),
                    ),
                  ),
                Flexible(child: Padding(padding: padding, child: builder(ctx))),
              ],
            ),
          ),
        ),
      );
    },
  );
}
