import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, FileOptions;
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/koala_ds.dart';
import '../core/theme/koala_tokens.dart';
import '../helpers/paywall_router.dart';
import '../providers/pro_status_provider.dart';
import '../services/analytics_service.dart';
import '../services/auth_token_service.dart';
import '../services/billing_service.dart';
import '../services/evlumba_live_service.dart';
import '../services/saved_items_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/koala_back_button.dart';
import 'admin/admin_shell.dart';
import 'auth_common.dart';
import 'auth_entry_screen.dart';
import 'legal_sheet.dart';
import 'profile_tab_screen.dart' show showProApplicationSheet;

/// Profile / Settings — simple, modern, well-organized.
/// SnapHome-inspired structure:
///   header card → koral Pro banner → Hesap / Genel / Hakkında / Hesap Yönetimi.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _user = FirebaseAuth.instance.currentUser;
  String? _photoUrl;
  String _displayName = '';
  String _email = '';
  String _phone = '';
  int _adminTapCount = 0;

  bool _wiping = false;
  bool _deleting = false;
  bool _restoring = false;
  // 2026-06-02: Yayınlanan tasarımlar herkese açık swipe'da görünsün mü.
  // Kullanıcı isteği: VARSAYILAN AÇIK. Satır yoksa/null ise true gösterilir.
  bool _showInSwipe = true;
  bool _showInSwipeBusy = false;

  // Sürüm artık build-time --dart-define=APP_VERSION ile pubspec'ten gelir
  // (CI + build_web.ps1 + build_android.ps1 hepsi geçiriyor). Define yoksa
  // (örn. salt `flutter run`) defaultValue gösterilir. Elle bumplamak yok.
  static const String _appVersionRaw =
      String.fromEnvironment('APP_VERSION', defaultValue: '');
  static String get _appVersion =>
      _appVersionRaw.isEmpty ? '1.0.171' : _appVersionRaw.split('+').first;
  static const String _supportEmail = 'info@evlumba.com';
  static const String _feedbackEmail = 'info@evlumba.com';
  static const String _shareUrl = 'https://www.evlumba.com';
  // Google Play abonelik yönetim sayfası — uygulama içinden abonelik iptali
  // Google politikası gereği mümkün değil; kullanıcı buraya yönlendirilir.
  static const String _playSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions';
  static const String _wipeDataEndpoint =
      'https://koala-api-olive.vercel.app/api/account/wipe-data';
  // TODO: confirm Play Store package name + iOS App Store id.
  static const String _androidPackage = 'com.evlumba.koala';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=$_androidPackage';
  static const String _appStoreUrl =
      'https://apps.apple.com/app/id0000000000'; // TODO: real iOS app id

  // ─── Palette (per spec) ────────────────────────────────────────
  static const Color _screenBg = KoalaColors.bg;
  static const Color _proPurple1 = KoalaDS.accent;
  static const Color _proPurple2 = KoalaDS.accentDeep;
  static const Color _sectionLabel = KoalaDS.inkSoft;
  static const Color _dangerRed = KoalaDS.danger;

  @override
  void initState() {
    super.initState();
    Analytics.screenViewed('profile');
    _displayName = _user?.displayName ?? '';
    _email = _user?.email ?? '';
    _photoUrl = _user?.photoURL;
    _loadShowInSwipe();
  }

  Future<void> _loadShowInSwipe() async {
    final uid = _user?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('koala_user_profiles')
          .select('show_designs_in_swipe, contact_info')
          .eq('uid', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        // 2026-06-02: VARSAYILAN AÇIK. Satır yoksa veya değer null ise true.
        final v = row?['show_designs_in_swipe'];
        _showInSwipe = v == null ? true : v == true;
        // Telefon — önce profil contact_info.phone, yoksa Firebase phoneNumber.
        final contact = row?['contact_info'];
        final cPhone = contact is Map ? (contact['phone'] ?? '').toString() : '';
        _phone = cPhone.isNotEmpty ? cPhone : (_user?.phoneNumber ?? '');
      });
    } catch (_) {/* sessiz — varsayılan açık */}
  }

  Future<void> _toggleShowInSwipe(bool on) async {
    if (_showInSwipeBusy) return;
    setState(() {
      _showInSwipe = on; // optimistic
      _showInSwipeBusy = true;
    });
    try {
      await Supabase.instance.client
          .rpc('koala_set_show_in_swipe', params: {'p_on': on});
    } catch (_) {
      if (mounted) setState(() => _showInSwipe = !on); // geri al
    } finally {
      if (mounted) setState(() => _showInSwipeBusy = false);
    }
  }

  bool get _isAnonymous => _user?.isAnonymous ?? true;

  // ─── Actions ──────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoalaRadius.lg)),
        title: const Text('Çıkış Yap', style: KoalaText.h3),
        content: const Text(
            'Hesabından çıkış yapmak istediğine emin misin?',
            style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                color: KoalaColors.textMed)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: KoalaColors.errorBright),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => const AuthEntryScreen(mode: AuthFlowMode.login)),
      (route) => false,
    );
  }

  void _goToLogin() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
          builder: (_) => const AuthEntryScreen(mode: AuthFlowMode.login)),
    );
  }

  Future<bool> _callWipeDataApi() async {
    final uid = _user?.uid;
    if (uid == null) return false;
    try {
      final headers = {
        ...await AuthTokenService.authHeaders(),
        'Content-Type': 'application/json',
      };
      final res = await http.post(
        Uri.parse(_wipeDataEndpoint),
        headers: headers,
        body: jsonEncode({'userId': uid}),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('wipe-data ok: ${res.body}');
        return true;
      }
      debugPrint('wipe-data failed ${res.statusCode}: ${res.body}');
      return false;
    } catch (e) {
      debugPrint('wipe-data error: $e');
      return false;
    }
  }

  void _clearLocalCaches() {
    SavedItemsService.prefetchedProjects = null;
    EvlumbaLiveService.prefetchedDeck = null;
  }

  Future<void> _wipeData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoalaRadius.lg)),
        title: const Text('Verilerini Sil', style: KoalaText.h3),
        content: const Text(
          'Tüm tasarımların, kayıtların, koleksiyonların ve AI sohbet geçmişin '
          'kalıcı olarak silinecek. Hesabın açık kalır. Devam edilsin mi?',
          style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              height: 1.45,
              color: KoalaColors.textMed),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _dangerRed),
            child: const Text('Verilerimi Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _wiping = true);
    final ok = await _callWipeDataApi();
    if (!mounted) return;
    setState(() => _wiping = false);

    if (ok) {
      _clearLocalCaches();
      _toast('Verilerin silindi', success: true);
    } else {
      _toast('Veriler silinemedi, tekrar dene', success: false);
    }
  }

  Future<void> _deleteAccount() async {
    final isPro = ref.read(proStatusProvider).value?.isPro ?? false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoalaRadius.lg)),
        title: const Text('Hesabımı Sil',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _dangerRed)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hesabın ve TÜM verilerin kalıcı olarak silinecek. '
              'Bu işlem GERİ ALINAMAZ. Devam etmek istediğinden emin misin?',
              style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  height: 1.45,
                  color: KoalaColors.textMed),
            ),
            // Aktif aboneliği olan kullanıcıyı uyar — hesap silmek Google Play
            // aboneliğini iptal etmez, Google faturalandırmaya devam eder.
            if (isPro) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF6C97A)),
                ),
                child: const Text(
                  '⚠️ Aktif bir Pro aboneliğin var. Hesabını silmek '
                  'aboneliğini İPTAL ETMEZ — Google seni faturalandırmaya '
                  'devam eder. Önce Google Play > Abonelikler bölümünden '
                  'aboneliğini iptal etmelisin.',
                  style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 12.5,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A5A00)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _dangerRed),
            child: const Text('Hesabımı Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deleting = true);

    final wiped = await _callWipeDataApi();
    if (!wiped) {
      if (mounted) {
        setState(() => _deleting = false);
        _toast('Veriler silinemedi, hesap silme iptal edildi',
            success: false);
      }
      return;
    }

    try {
      await FirebaseAuth.instance.currentUser?.delete();
      _clearLocalCaches();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => const AuthEntryScreen(mode: AuthFlowMode.login)),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('account delete error: ${e.code} ${e.message}');
      if (!mounted) return;
      setState(() => _deleting = false);
      if (e.code == 'requires-recent-login') {
        _toast('Lütfen önce çıkış yap, tekrar giriş yap ve sonra tekrar dene',
            success: false);
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) await _logout();
      } else {
        _toast('Hesap silinemedi: ${e.message ?? e.code}', success: false);
      }
    } catch (e) {
      debugPrint('account delete error: $e');
      if (!mounted) return;
      setState(() => _deleting = false);
      _toast('Hesap silinemedi, tekrar dene', success: false);
    }
  }

  Future<void> _restorePurchases() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final ok = await BillingService.restorePurchases();
      if (!mounted) return;
      _toast(
        ok ? 'Satın alımlar geri yüklendi' : 'Geri yüklenecek satın alım yok',
        success: ok,
      );
    } catch (e) {
      debugPrint('restorePurchases error: $e');
      if (mounted) _toast('Geri yükleme başarısız, tekrar dene', success: false);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// Aboneliği yönet / iptal et. Uygulama içinden Google Play aboneliği
  /// iptal etmek Google politikası gereği mümkün değil — kullanıcı onaydan
  /// sonra Google Play abonelik sayfasına yönlendirilir, iptal orada yapılır.
  Future<void> _manageSubscription() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoalaRadius.lg)),
        title: const Text('Aboneliği Yönet', style: KoalaText.h3),
        content: const Text(
          'Aboneliğini Google Play üzerinden yönetebilir veya iptal '
          'edebilirsin. Devam edersen Google Play abonelik sayfasına '
          'yönlendirileceksin; iptal işlemi orada tamamlanır.',
          style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              height: 1.45,
              color: KoalaColors.textMed),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: KoalaColors.accentDeep),
            child: const Text("Google Play'e Git"),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _openExternal(_playSubscriptionsUrl);
  }

  Future<void> _shareApp() async {
    try {
      if (kIsWeb) {
        await Clipboard.setData(const ClipboardData(text: _shareUrl));
        if (mounted) _toast('Bağlantı kopyalandı', success: true);
        return;
      }
      await Share.share('Koala ile evini AI ile tasarla → $_shareUrl');
    } catch (e) {
      debugPrint('share error: $e');
      if (mounted) _toast('Paylaşılamadı, tekrar dene');
    }
  }

  void _rateApp() {
    // Best-effort: route to Play Store on Android, App Store on iOS, web → Play.
    String url = _playStoreUrl;
    try {
      if (!kIsWeb && Platform.isIOS) url = _appStoreUrl;
    } catch (_) {}
    _openExternal(url);
  }

  Future<void> _openFeedback() async {
    final mailto = Uri.parse(
        'mailto:$_feedbackEmail?subject=${Uri.encodeComponent('Koala Geri Bildirim')}');
    try {
      if (kIsWeb) {
        html.window.open(mailto.toString(), '_self');
        return;
      }
      final ok = await launchUrl(mailto);
      if (ok) return;
    } catch (e) {
      debugPrint('feedback mailto error: $e');
    }
    await Clipboard.setData(const ClipboardData(text: _feedbackEmail));
    if (mounted) _toast('E-posta kopyalandı: $_feedbackEmail', success: true);
  }

  void _openFaq() {
    const faqs = <_FaqItem>[
      _FaqItem(
        q: 'AI tasarım nasıl çalışıyor?',
        a:
            'Mekan fotoğrafını yükle, Koala görseli analiz eder ve seçtiğin tarza göre yeni bir tasarım üretir.',
      ),
      _FaqItem(
        q: 'Tasarımlarım kaydediliyor mu?',
        a:
            'Evet. Ürettiğin tüm tasarımlar otomatik kaydedilir; Kaydedilenlerim ve Koleksiyonlarım üzerinden erişebilirsin.',
      ),
      _FaqItem(
        q: 'Profesyonele nasıl ulaşabilirim?',
        a:
            'Tasarımcı profilinde "Mesaj" butonuyla doğrudan iletişime geçebilir, projen için teklif alabilirsin.',
      ),
      _FaqItem(
        q: 'Hesabımı nasıl silerim?',
        a:
            'Profil sayfasının en altındaki "Hesap Yönetimi" bölümünden hesabını ve verilerini silebilirsin.',
      ),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoalaRadius.lg)),
        title: const Text('Sıkça Sorulanlar', style: KoalaText.h3),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < faqs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Text(faqs[i].q,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: KoalaColors.text,
                      )),
                  const SizedBox(height: 4),
                  Text(faqs[i].a,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        height: 1.45,
                        color: KoalaColors.textMed,
                      )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat')),
        ],
      ),
    );
  }

  // ─── UI helpers ─────────────────────────────────────────────────
  void _toast(String message, {bool? success}) {
    final color = success == null
        ? KoalaColors.text
        : (success ? KoalaColors.greenBright : KoalaColors.errorBright);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
        content: Text(
          message,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ));
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/');
  }

  void _onAdminTap() {
    _adminTapCount++;
    if (_adminTapCount >= 5) {
      _adminTapCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminShell()),
      );
    }
  }

  Future<void> _openExternal(String url) async {
    try {
      if (kIsWeb) {
        html.window.open(url, '_blank');
        return;
      }
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _toast('Bağlantı açılamadı');
    } catch (e) {
      debugPrint('Open URL error: $e');
      if (mounted) _toast('Bağlantı açılamadı');
    }
  }

  Future<void> _contactSupport() async {
    final mailto = Uri.parse(
        'mailto:$_supportEmail?subject=${Uri.encodeComponent('Koala Destek')}');
    try {
      if (kIsWeb) {
        html.window.open(mailto.toString(), '_self');
        return;
      }
      final ok = await launchUrl(mailto);
      if (ok) return;
    } catch (e) {
      debugPrint('mailto error: $e');
    }
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (mounted) _toast('E-posta kopyalandı: $_supportEmail', success: true);
  }

  bool _avatarUploading = false;

  Future<void> _tapAvatarEdit() async {
    HapticFeedback.selectionClick();
    final user = FirebaseAuth.instance.currentUser;
    final hasPhoto = (user?.photoURL ?? '').isNotEmpty;
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KoalaColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(height: 14),
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(LucideIcons.camera,
                      color: KoalaColors.accentDeep),
                  title: const Text('Fotoğraf çek'),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
              ListTile(
                leading:
                    const Icon(LucideIcons.image, color: KoalaColors.accentDeep),
                title: const Text('Galeriden seç'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (hasPhoto)
                ListTile(
                  leading:
                      const Icon(LucideIcons.trash2, color: Colors.redAccent),
                  title: const Text('Mevcut fotoğrafı kaldır',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
              ListTile(
                leading: const Icon(LucideIcons.x, color: KoalaColors.textSec),
                title: const Text('İptal'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'remove') {
      await _removeAvatar();
    } else {
      await _pickAndUploadAvatar(
        source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource src) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: src,
        maxWidth: 720,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      setState(() => _avatarUploading = true);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('not_authenticated');
      final bytes = await picked.readAsBytes();
      final objectPath = '$uid/avatar.webp';
      final storage = Supabase.instance.client.storage.from('avatars');
      await storage.uploadBinary(
        objectPath,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/webp',
        ),
      );
      final v = DateTime.now().millisecondsSinceEpoch;
      final publicUrl = '${storage.getPublicUrl(objectPath)}?v=$v';
      await Future.wait([
        FirebaseAuth.instance.currentUser!.updatePhotoURL(publicUrl),
        UserProfileService.setAvatarUrl(publicUrl),
      ]);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _toast('Profil fotoğrafın güncellendi ✨', success: true);
    } catch (e) {
      debugPrint('[settings-avatar] upload failed: $e');
      if (mounted) _toast('Fotoğraf yüklenemedi');
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fotoğrafı kaldır'),
        content: const Text(
            'Profil fotoğrafın silinecek. Onaylıyor musun?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaldır',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      setState(() => _avatarUploading = true);
      await Future.wait([
        FirebaseAuth.instance.currentUser!.updatePhotoURL(null),
        UserProfileService.setAvatarUrl(null),
      ]);
      if (!mounted) return;
      _toast('Profil fotoğrafı kaldırıldı', success: true);
    } catch (e) {
      debugPrint('[settings-avatar] remove failed: $e');
      if (mounted) _toast('Kaldırılamadı');
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  void _openLanguagePicker() {
    // TODO: implement language picker (no LanguageService in app yet).
    _toast('Dil seçimi · Yakında');
  }

  // ─── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final asyncStatus = ref.watch(proStatusProvider);
    final proStatus = asyncStatus.value;
    final isPro = proStatus?.isPro ?? false;

    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          // SafeArea bottom:false olduğu için liste alt padding'ine sistem
          // navigasyon çubuğu (viewPadding.bottom) eklenir — gesture nav'lı
          // cihazlarda "Hesap Yönetimi" bölümü kesilmesin.
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 40 + MediaQuery.of(context).viewPadding.bottom),
          children: [
            // Header — canonical app style (matches Tarzını Keşfet / Projelerim)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  KoalaBackButton(
                    onTap: _goBack,
                    padding: const EdgeInsets.only(right: 10),
                  ),
                  GestureDetector(
                    onTap: _onAdminTap,
                    behavior: HitTestBehavior.opaque,
                    child: const Text(
                      'Ayarlar',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: KoalaColors.text,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildHeaderCard(),
            const SizedBox(height: 16),
            _buildBecomeProDesignerCta(),
            const SizedBox(height: 20),
            _buildProBanner(isPro, proStatus?.proUntil),
            const SizedBox(height: 24),

            // ─── Hesap
            const _SectionHeader('HESAP'),
            _SettingsCard(rows: [
              if (!_isAnonymous && _email.isNotEmpty)
                _SettingsTile(
                  icon: LucideIcons.mail,
                  label: 'E-posta',
                  trailing: _email,
                ),
              if (!_isAnonymous && _phone.isNotEmpty)
                _SettingsTile(
                  icon: LucideIcons.phone,
                  label: 'Telefon',
                  trailing: _phone,
                ),
              if (!_isAnonymous)
                _SettingsTile(
                  icon: LucideIcons.logOut,
                  label: 'Çıkış yap',
                  onTap: _logout,
                ),
              if (_isAnonymous)
                _SettingsTile(
                  icon: LucideIcons.logIn,
                  label: 'Giriş yap',
                  onTap: _goToLogin,
                ),
              _SettingsTile(
                icon: LucideIcons.lifeBuoy,
                label: 'Bize ulaşın',
                onTap: _contactSupport,
              ),
              _SettingsTile(
                icon: LucideIcons.helpCircle,
                label: 'SSS',
                onTap: _openFaq,
              ),
            ]),
            const SizedBox(height: 24),

            // ─── Genel
            const _SectionHeader('GENEL'),
            _SettingsCard(rows: [
              // Opt-in: yayınladığın tasarımlar Tarzını Keşfet (swipe) akışında
              // başkalarına gösterilsin mi. Varsayılan kapalı.
              if (!_isAnonymous)
                _SettingsTile(
                  icon: LucideIcons.sparkles,
                  label: 'Tasarımlarım keşfette görünsün',
                  trailingWidget: Switch.adaptive(
                    value: _showInSwipe,
                    onChanged: _showInSwipeBusy ? null : _toggleShowInSwipe,
                    activeTrackColor: KoalaColors.accentDeep,
                  ),
                ),
              _SettingsTile(
                icon: LucideIcons.languages,
                label: 'Dil',
                trailing: 'Türkçe',
                onTap: _openLanguagePicker,
              ),
              // Magaza yapilandirilmadiysa (iOS'ta RC anahtari yok) gizle —
              // calismayan satin alma UI'si App Review reddi (2.1).
              if (BillingService.purchasesConfigured)
                _SettingsTile(
                  icon: LucideIcons.shoppingCart,
                  label: 'Satın Alımları Geri Yükle',
                  onTap: _restoring ? null : _restorePurchases,
                  trailingWidget: _restoring
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KoalaColors.accentDeep,
                          ),
                        )
                      : null,
                ),
            ]),
            const SizedBox(height: 24),

            // ─── Abonelik (yalnızca aktif Pro üyelerde görünür)
            if (isPro) ...[
              const _SectionHeader('ABONELİK'),
              _SettingsCard(rows: [
                _SettingsTile(
                  icon: LucideIcons.creditCard,
                  label: 'Aboneliği Yönet',
                  onTap: _manageSubscription,
                ),
              ]),
              const SizedBox(height: 24),
            ],

            // ─── Hakkında
            const _SectionHeader('HAKKINDA'),
            _SettingsCard(rows: [
              _SettingsTile(
                icon: LucideIcons.thumbsUp,
                label: 'Bizi Değerlendirin',
                onTap: _rateApp,
              ),
              _SettingsTile(
                icon: LucideIcons.messageCircle,
                label: 'Geri Bildirim',
                onTap: _openFeedback,
              ),
              _SettingsTile(
                icon: LucideIcons.share2,
                label: 'Uygulamamızı Paylaş',
                onTap: _shareApp,
              ),
              _SettingsTile(
                icon: LucideIcons.shield,
                label: 'Gizlilik Politikası',
                onTap: () => showLegalSheet(context, LegalDoc.privacy),
              ),
              _SettingsTile(
                icon: LucideIcons.fileText,
                label: 'Kullanım Şartları',
                onTap: () => showLegalSheet(context, LegalDoc.terms),
              ),
              _SettingsTile(
                icon: LucideIcons.gavel,
                label: 'KVKK Aydınlatma Metni',
                onTap: () => showLegalSheet(context, LegalDoc.kvkk),
              ),
              _SettingsTile(
                icon: LucideIcons.info,
                label: 'Versiyon',
                trailing: _appVersion,
              ),
            ]),

            if (!_isAnonymous) ...[
              const SizedBox(height: 24),
              const _SectionHeader('HESAP YÖNETIMI'),
              _SettingsCard(rows: [
                _SettingsTile(
                  icon: LucideIcons.trash2,
                  label: 'Verilerimi sil',
                  danger: true,
                  onTap: (_wiping || _deleting) ? null : _wipeData,
                  trailingWidget: _wiping
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: _dangerRed),
                        )
                      : null,
                ),
                _SettingsTile(
                  icon: LucideIcons.userX,
                  label: 'Hesabımı sil',
                  danger: true,
                  onTap: (_wiping || _deleting) ? null : _deleteAccount,
                  trailingWidget: _deleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: _dangerRed),
                        )
                      : null,
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  // ─── "Profesyonel ol" CTA — compact elegant tile (~88px) ───────────
  // Hides if already an approved professional designer (profile.isPro) or
  // if there is already an approved application. Pending/rejected/none all
  // surface the CTA with state-specific copy.
  //
  // NOTE: The previous 180px hero card used `koala-seed/pro-cta/hero-v1.webp`
  // as full-width background. The image is now displayed inside the
  // ProApplicationSheet header (in profile_tab_screen.dart) so the
  // Gemini-generated asset still has a use case.
  Widget _buildBecomeProDesignerCta() {
    final bundle = ref.watch(userProfileProvider).asData?.value;
    final profile = bundle?.profile;
    final app = bundle?.application ?? ProApplicationStatus.none;
    final alreadyDesigner = profile?.isPro == true || app.isApproved;
    if (alreadyDesigner) return const SizedBox.shrink();

    final pending = app.isPending;
    final rejected = app.isRejected;

    // State-driven copy. Wording preserved from previous hero card.
    final String title;
    final String subtitle;
    final IconData icon;
    final Color accentLine;
    if (pending) {
      title = 'Başvurun değerlendiriliyor';
      subtitle = 'Evlumba ekibi en kısa sürede dönüş yapacak.';
      icon = LucideIcons.clock;
      accentLine = _proPurple1;
    } else if (rejected) {
      title = 'Başvurunu güçlendir, sahneye çık';
      subtitle = 'Yeşil tik ve tasarım paylaşma seni bekliyor.';
      icon = LucideIcons.refreshCcw;
      accentLine = const Color(0xFFE5C879);
    } else {
      title = 'Tasarımlarını dünyayla buluştur';
      subtitle = 'Müşterilerle eşleş, projeler al, kazan.';
      icon = LucideIcons.sparkles;
      accentLine = const Color(0xFFE5C879);
    }

    final tapEnabled = !pending;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: tapEnabled
            ? () async {
                final submitted = await showProApplicationSheet(context);
                if (submitted == true && mounted) {
                  ref.invalidate(userProfileProvider);
                }
              }
            : null,
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                // 4px gold/purple accent strip on the left edge.
                Container(width: 4, color: accentLine),
                const SizedBox(width: 12),
                // Icon tile
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _proPurple1.withValues(alpha: 0.12),
                        _proPurple2.withValues(alpha: 0.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: _proPurple1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.text,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: _sectionLabel,
                          height: 1.3,
                          letterSpacing: -0.05,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tapEnabled)
                  const Padding(
                    padding: EdgeInsets.only(right: 12, left: 6),
                    child: Icon(LucideIcons.chevronRight,
                        size: 20, color: KoalaDS.inkFaint),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header card (avatar + name + email) ───────────────────────
  Widget _buildHeaderCard() {
    final initial = _displayName.isNotEmpty
        ? _displayName.characters.first.toUpperCase()
        : (_email.isNotEmpty ? _email.characters.first.toUpperCase() : 'K');
    final shownName = _displayName.isNotEmpty
        ? _displayName
        : (_isAnonymous ? 'Misafir' : 'Koala kullanıcısı');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar + edit pencil overlay
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: KoalaDS.accentGradient,
                  ),
                  child: ClipOval(
                    child: _photoUrl != null && _photoUrl!.isNotEmpty
                        ? Image.network(
                            _photoUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: (72 *
                                    MediaQuery.of(context).devicePixelRatio)
                                .round(),
                            errorBuilder: (_, __, ___) =>
                                _initialAvatar(initial),
                          )
                        : _initialAvatar(initial),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _tapAvatarEdit,
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(LucideIcons.pencil,
                            size: 13, color: KoalaColors.text),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shownName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    letterSpacing: -0.2,
                  ),
                ),
                if (_email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _sectionLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _initialAvatar(String letter) => Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      );

  // ─── Koala Pro banner (purple gradient + furniture image) ─────
  Widget _buildProBanner(bool isPro, DateTime? proUntil) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: KoalaDS.accentGradient,
        boxShadow: [
          BoxShadow(
            color: _proPurple1.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Full-width image, soft horizontal mask blends image into purple
            // bg across a wide ~25% seam — no hard edge.
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.42, 0.72, 1.0],
                ).createShader(rect),
                child: Image.asset(
                  'assets/pro/hero_1.webp',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            // Subtle purple inner glow at the seam — purely cosmetic warmth.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _proPurple1.withValues(alpha: 0.0),
                        _proPurple1.withValues(alpha: 0.0),
                        _proPurple2.withValues(alpha: 0.22),
                        _proPurple1.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.40, 0.55, 0.75],
                    ),
                  ),
                ),
              ),
            ),
            // Content (left 60%)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Koala Pro',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isPro
                              ? 'Tüm Pro özellikler aktif. Teşekkürler!'
                              : 'Tüm Pro özelliklerin kilidini aç',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                            color: Colors.white.withValues(alpha: 0.92),
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (isPro)
                          _ProActivePill(until: proUntil)
                        else
                          _UpgradePill(
                            onTap: () => showPaywall(context,
                                trigger: 'profile_upgrade_button'),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Building blocks
// ═══════════════════════════════════════════════════════════

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: KoalaDS.inkSoft,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((w) => w is! SizedBox).toList();
    final children = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      children.add(visible[i]);
      if (i != visible.length - 1) {
        children.add(const Padding(
          padding: EdgeInsets.only(left: 60, right: 16),
          child: Divider(height: 1, color: KoalaDS.line),
        ));
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.trailingWidget,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final String? trailing;
  final Widget? trailingWidget;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final hasChevron = onTap != null;
    const dangerRed = KoalaDS.danger;
    final labelColor = danger ? dangerRed : KoalaColors.text;
    final iconColor = danger ? dangerRed : KoalaColors.text;
    final iconBg = danger ? KoalaDS.dangerTint : KoalaDS.surfaceMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (trailingWidget != null)
                Padding(
                  padding: EdgeInsets.only(right: hasChevron ? 6 : 0),
                  child: trailingWidget!,
                )
              else if (trailing != null && trailing!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(right: hasChevron ? 6 : 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      trailing!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: KoalaDS.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              if (hasChevron)
                Icon(LucideIcons.chevronRight,
                    size: 18,
                    color: danger
                        ? dangerRed.withValues(alpha: 0.55)
                        : KoalaDS.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpgradePill extends StatelessWidget {
  const _UpgradePill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            "PRO'ya yükselt",
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: KoalaDS.accent,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProActivePill extends StatelessWidget {
  const _ProActivePill({this.until});
  final DateTime? until;

  String _fmt(DateTime d) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.check, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            until != null ? 'Pro Üye · ${_fmt(until!)}' : 'Pro Üye',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
