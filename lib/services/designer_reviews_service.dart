// Tasarımcı / pro kullanıcı yorumları — koala_designer_reviews tablosu.
//
// Şema (best-effort; defansif okuma):
//   - id (uuid)
//   - designer_id (text, viewed user uid)
//   - reviewer_id (text, current user uid)
//   - rating (int, 1..5)
//   - comment (text, nullable)
//   - created_at (timestamptz)
//
// Notlar:
// - Self-review yasak — write site (submit) bunu reddeder; UI da gizler.
// - Tablo/şema yoksa try/catch ile sessiz boş döner (migration yok kuralı).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

class DesignerReview {
  final String id;
  final String designerId;
  final String reviewerId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  // Reviewer enrichment (best-effort, ayrı fetch'ten doldurulur).
  final String? reviewerName;
  final String? reviewerAvatarUrl;

  const DesignerReview({
    required this.id,
    required this.designerId,
    required this.reviewerId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.reviewerName,
    this.reviewerAvatarUrl,
  });

  factory DesignerReview.fromRow(Map<String, dynamic> r) => DesignerReview(
        id: (r['id'] ?? '').toString(),
        designerId: (r['designer_id'] ?? '').toString(),
        reviewerId: (r['reviewer_id'] ?? '').toString(),
        rating: (r['rating'] is num) ? (r['rating'] as num).toInt() : 0,
        comment: r['comment']?.toString(),
        createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );

  DesignerReview copyWith({String? reviewerName, String? reviewerAvatarUrl}) =>
      DesignerReview(
        id: id,
        designerId: designerId,
        reviewerId: reviewerId,
        rating: rating,
        comment: comment,
        createdAt: createdAt,
        reviewerName: reviewerName ?? this.reviewerName,
        reviewerAvatarUrl: reviewerAvatarUrl ?? this.reviewerAvatarUrl,
      );
}

class DesignerReviewsResult {
  final List<DesignerReview> reviews;
  final double avg;
  final int count;
  const DesignerReviewsResult({
    required this.reviews,
    required this.avg,
    required this.count,
  });
  static const empty =
      DesignerReviewsResult(reviews: <DesignerReview>[], avg: 0, count: 0);
}

class DesignerReviewsService {
  DesignerReviewsService._();

  static const String _table = 'koala_designer_reviews';

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Bir tasarımcı/pro için son yorumlar + ortalama + adet.
  /// Maksimum [limit] kayıt çekilir (avg/count client-side hesaplanır).
  static Future<DesignerReviewsResult> getForDesigner(
    String designerId, {
    int limit = 50,
  }) async {
    if (designerId.isEmpty) return DesignerReviewsResult.empty;
    try {
      final data = await Supabase.instance.client
          .from(_table)
          .select('id, designer_id, reviewer_id, rating, comment, created_at')
          .eq('designer_id', designerId)
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(data)
          .map(DesignerReview.fromRow)
          .where((r) => r.rating > 0)
          .toList();
      if (rows.isEmpty) {
        return const DesignerReviewsResult(
            reviews: <DesignerReview>[], avg: 0, count: 0);
      }
      final sum = rows.fold<int>(0, (a, r) => a + r.rating);
      final avg = sum / rows.length;
      return DesignerReviewsResult(
        reviews: rows,
        avg: avg,
        count: rows.length,
      );
    } catch (e) {
      debugPrint('[DesignerReviewsService] getForDesigner failed: $e');
      return DesignerReviewsResult.empty;
    }
  }

  /// Yeni yorum gönder. Self-review yasak.
  /// Başarılıysa true döner.
  static Future<bool> submit({
    required String designerId,
    required int rating,
    String? comment,
  }) async {
    final uid = _uid;
    if (uid == null || designerId.isEmpty) return false;
    if (uid == designerId) return false; // self-review reddedildi.
    if (rating < 1 || rating > 5) return false;
    try {
      await Supabase.instance.client.from(_table).insert({
        'designer_id': designerId,
        'reviewer_id': uid,
        'rating': rating,
        if ((comment ?? '').trim().isNotEmpty) 'comment': comment!.trim(),
      });
      return true;
    } catch (e) {
      debugPrint('[DesignerReviewsService] submit failed: $e');
      return false;
    }
  }
}
