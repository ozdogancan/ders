import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/saved_items_service.dart';

/// Kaydedilen öğe sayıları (profil, badge vb.)
final savedCountsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  return SavedItemsService.getCounts();
});

/// Toplam kayıt sayısı
final totalSavedCountProvider = Provider.autoDispose<int>((ref) {
  final counts = ref.watch(savedCountsProvider).asData?.value ?? {};
  return counts.values.fold(0, (a, b) => a + b);
});
