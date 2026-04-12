import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ürün gösterim ve tıklama analitiklerini Supabase'e kaydeder.
/// Tablo: product_events (user_id, product_id, product_name, shop_name, price, url, event_type, source)
class ProductAnalyticsService {
  const ProductAnalyticsService._();

  static SupabaseClient? get _db {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Supabase henüz initialize olmamış
    }
  }

  static String? get _userId => _db?.auth.currentUser?.id;

  /// Ürün gösterildiğinde çağır (impression)
  static Future<void> trackImpression({
    required String productId,
    required String productName,
    String shopName = '',
    String price = '',
    String url = '',
    String source = '',
    String? conversationId,
  }) async {
    await _track(
      eventType: 'impression',
      productId: productId,
      productName: productName,
      shopName: shopName,
      price: price,
      url: url,
      source: source,
      conversationId: conversationId,
    );
  }

  /// Ürüne tıklandığında çağır (click)
  static Future<void> trackClick({
    required String productId,
    required String productName,
    String shopName = '',
    String price = '',
    String url = '',
    String source = '',
    String? conversationId,
  }) async {
    await _track(
      eventType: 'click',
      productId: productId,
      productName: productName,
      shopName: shopName,
      price: price,
      url: url,
      source: source,
      conversationId: conversationId,
    );
  }

  /// Ürün kaydedildiğinde çağır (save)
  static Future<void> trackSave({
    required String productId,
    required String productName,
    String shopName = '',
    String price = '',
    String source = '',
  }) async {
    await _track(
      eventType: 'save',
      productId: productId,
      productName: productName,
      shopName: shopName,
      price: price,
      source: source,
    );
  }

  static Future<void> _track({
    required String eventType,
    required String productId,
    required String productName,
    String shopName = '',
    String price = '',
    String url = '',
    String source = '',
    String? conversationId,
  }) async {
    try {
      final db = _db;
      final userId = _userId;
      if (db == null || userId == null) return; // Supabase hazır değil veya giriş yapılmamış

      await db.from('product_events').insert({
        'user_id': userId,
        'product_id': productId,
        'product_name': productName,
        'shop_name': shopName,
        'price': price,
        'url': url,
        'event_type': eventType,
        'source': source,
        'conversation_id': conversationId,
      });
    } catch (e) {
      // Analitik hatası sessiz — kullanıcıyı etkilemez
      debugPrint('ProductAnalyticsService: $eventType track failed: $e');
    }
  }
}
