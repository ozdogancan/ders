import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// Uygulama içi yasal belge görüntüleyici — aşağıdan yukarı kayan, tamamen
/// kaydırılabilir ve kolayca kapatılabilen (kapat butonu, aşağı sürükleme,
/// dışına dokunma) bir alt-sayfa. Gizlilik Politikası ve Kullanım Şartları
/// için kullanılır — kullanıcı dış tarayıcıya çıkmadan okur.
enum LegalDoc { privacy, terms, kvkk }

Future<void> showLegalSheet(BuildContext context, LegalDoc doc) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _LegalSheet(doc: doc),
  );
}

class _LegalSheet extends StatelessWidget {
  const _LegalSheet({required this.doc});
  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final c = doc == LegalDoc.privacy
        ? _privacy
        : doc == LegalDoc.terms
            ? _terms
            : _kvkk;

    return Container(
      height: size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Sürükleme tutamacı.
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9E3),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          // Başlık + kapat butonu.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.title,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: KoalaColors.text,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.x,
                        size: 18, color: KoalaColors.text),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEDEDF2)),
          // Kaydırılabilir içerik.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  'Son güncelleme: ${c.updated}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KoalaColors.textTer,
                  ),
                ),
                const SizedBox(height: 18),
                for (final s in c.sections) ..._renderSection(s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _renderSection(_LegalSection s) {
    return [
      Text(
        s.heading,
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          color: KoalaColors.text,
          letterSpacing: -0.2,
        ),
      ),
      const SizedBox(height: 8),
      for (final p in s.body) _paragraph(p),
      const SizedBox(height: 20),
    ];
  }

  Widget _paragraph(String text) {
    final isBullet = text.startsWith('• ');
    final body = isBullet ? text.substring(2) : text;
    final textWidget = Text(
      body,
      style: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13.5,
        height: 1.55,
        fontWeight: FontWeight.w500,
        color: KoalaColors.textMed,
      ),
    );
    if (!isBullet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: textWidget,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 9),
            child: SizedBox(
              width: 5,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF6C63FF),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(child: textWidget),
        ],
      ),
    );
  }
}

class _LegalContent {
  const _LegalContent({
    required this.title,
    required this.updated,
    required this.sections,
  });
  final String title;
  final String updated;
  final List<_LegalSection> sections;
}

class _LegalSection {
  const _LegalSection(this.heading, this.body);
  final String heading;
  final List<String> body;
}

// ─── Gizlilik Politikası ───────────────────────────────────────────────
const _LegalContent _privacy = _LegalContent(
  title: 'Gizlilik Politikası',
  updated: '16 Mart 2026',
  sections: [
    _LegalSection('Genel Bakış', [
      'Koala, Evlumba Software tarafından geliştirilen yapay zeka destekli iç mimari tasarım asistanıdır. Kullanıcılarımızın gizliliğine saygı duyuyor ve kişisel verilerin korunmasını önemsiyoruz.',
      'Bu gizlilik politikası, uygulamayı kullanırken hangi verilerin toplandığını, nasıl kullanıldığını ve nasıl korunduğunu açıklar.',
    ]),
    _LegalSection('Toplanan Veriler', [
      'Uygulamamız aşağıdaki verileri toplar:',
      '• Hesap bilgileri: Google hesabı ile giriş yapıldığında ad, e-posta adresi ve profil fotoğrafı.',
      '• Mekan ve ilham görselleri: Analiz veya stil paylaşımı için yüklediğin görseller.',
      '• Sohbet mesajları: AI asistan ve mesajlaşma akışları içindeki yazışmalar.',
      '• Kullanım verileri: Uygulama kullanım istatistikleri ve tercihler.',
      '• Cihaz bilgileri: Cihaz türü ve işletim sistemi sürümü (hata ayıklama amaçlı).',
    ]),
    _LegalSection('Verilerin Kullanımı', [
      'Topladığımız verileri şu amaçlarla kullanıyoruz:',
      '• İç mekan analizi, stil önerisi ve tasarım keşfi deneyimi sunmak.',
      '• Hesabını yönetmek ve kişiselleştirilmiş deneyim sunmak.',
      '• Uygulama performansını izlemek ve iyileştirmek.',
      '• Teknik sorunları tespit etmek ve gidermek.',
      '• Abonelik ve satın alma işlemlerini yönetmek.',
      'Verilerini hiçbir koşulda üçüncü taraf reklam ağlarıyla paylaşmıyoruz.',
    ]),
    _LegalSection('Kamera Kullanımı', [
      'Uygulamamız, mekan veya ilham görseli eklemen için cihazının kamerasına erişim isteyebilir. Kamera yalnızca sen aktif olarak kullandığında açılır.',
      'Kamera izni vermeden de galeriden görsel seçerek uygulamayı kullanabilirsin.',
    ]),
    _LegalSection('Veri Güvenliği', [
      'Verilerini korumak için aldığımız önlemler:',
      '• Tüm veri iletişimi SSL/TLS şifreleme ile korunur.',
      '• Kullanıcı verileri güvenli bulut sunucularında (Supabase, Firebase) saklanır.',
      '• Kimlik doğrulama Google OAuth 2.0 ile sağlanır.',
      '• Düzenli güvenlik kontrolleri yapılır.',
    ]),
    _LegalSection('Üçüncü Taraf Hizmetler', [
      'Uygulamamız şu üçüncü taraf hizmetleri kullanır:',
      '• Google Firebase: Kimlik doğrulama ve analitik.',
      '• Supabase: Veritabanı ve dosya depolama.',
      '• Google Gemini: Yapay zeka destekli tasarım ve içerik üretim motoru.',
      '• Google Play Billing: Abonelik ve ödeme işlemleri.',
      'Bu hizmet sağlayıcıların kendi gizlilik politikaları geçerlidir.',
    ]),
    _LegalSection('Kullanıcı Hakları', [
      'Aşağıdaki haklara sahipsin:',
      '• Erişim: Hakkında sakladığımız verileri talep edebilirsin.',
      '• Düzeltme: Yanlış verilerin düzeltilmesini isteyebilirsin.',
      '• Silme: Hesabının ve tüm verilerinin silinmesini talep edebilirsin (Profil > Hesap Yönetimi).',
      '• Taşınabilirlik: Verilerinin bir kopyasını talep edebilirsin.',
      'Bu haklarını kullanmak için info@evlumba.com adresine e-posta gönderebilirsin.',
    ]),
    _LegalSection('Çocukların Gizliliği', [
      'Uygulamamız 13 yaş ve üzeri kullanıcılar için tasarlanmıştır. 13 yaşın altındaki çocuklardan bilerek kişisel veri toplamıyoruz.',
    ]),
    _LegalSection('Değişiklikler', [
      'Bu gizlilik politikasını zaman zaman güncelleyebiliriz. Önemli değişikliklerde uygulama içi bildirim veya e-posta ile bilgilendirme yaparız.',
    ]),
    _LegalSection('İletişim', [
      'Gizlilik politikamızla ilgili sorular için:',
      '• E-posta: info@evlumba.com',
      '• Geliştirici: Evlumba Software',
    ]),
  ],
);

// ─── Kullanım Şartları ─────────────────────────────────────────────────
const _LegalContent _terms = _LegalContent(
  title: 'Kullanım Şartları',
  updated: '21 Mayıs 2026',
  sections: [
    _LegalSection('1. Hizmet Tanımı', [
      'Koala ("uygulama"), Evlumba Software tarafından sunulan yapay zeka destekli bir iç mimari tasarım ve ilham uygulamasıdır. Uygulama; mekan fotoğraflarının analizini, yapay zeka ile tasarım üretimini, stil keşfini ve tasarımcılarla iletişimi sağlar.',
      'Bu Kullanım Şartları, uygulamayı kullanarak kabul ettiğin koşulları düzenler. Uygulamayı kullanman, bu şartları okuduğun ve kabul ettiğin anlamına gelir.',
    ]),
    _LegalSection('2. Hesap ve Uygunluk', [
      'Uygulamayı kullanmak için en az 13 yaşında olmalısın. Hesabını Google ile oluşturabilirsin.',
      'Hesabının güvenliğinden ve hesabın altında gerçekleşen tüm işlemlerden sen sorumlusun. Hesap bilgilerini başkalarıyla paylaşmamalısın.',
    ]),
    _LegalSection('3. Abonelik, Ücretler ve Otomatik Yenileme', [
      'Uygulamanın bazı özellikleri ("Koala Pro") ücretli aboneliklerle sunulur. Abonelik satın alımları Google Play üzerinden gerçekleştirilir ve faturalandırılır.',
      'Abonelikler, sen iptal etmediğin sürece her dönem sonunda otomatik olarak yenilenir ve yenileme ücreti Google hesabından tahsil edilir.',
      '• Aboneliğini istediğin zaman Google Play > Abonelikler bölümünden iptal edebilirsin. İptal, içinde bulunduğun dönemin sonunda geçerli olur; o döneme ait ücret iade edilmez.',
      '• Sunulan ücretsiz deneme süresi, sen bitiminden önce iptal etmezsen otomatik olarak ücretli aboneliğe dönüşür.',
      '• Fiyatlar ve plan içerikleri zaman zaman güncellenebilir; değişiklikler önceden bildirilir.',
      'İade talepleri Google Play iade politikasına tabidir.',
    ]),
    _LegalSection('4. Yapay Zeka ile Üretilen İçerik', [
      'Uygulama, yapay zeka kullanarak tasarım görselleri ve öneriler üretir. Bu içerikler ilham ve görselleştirme amaçlıdır.',
      'Yapay zeka çıktıları her zaman doğru, eksiksiz veya uygulanabilir olmayabilir; profesyonel mimari, mühendislik veya inşaat danışmanlığının yerine geçmez. Uygulamadan alınan önerilere dayanarak yapacağın işlerden sen sorumlusun.',
    ]),
    _LegalSection('5. Kullanıcı Yükümlülükleri', [
      'Uygulamayı kullanırken:',
      '• Yalnızca üzerinde hak sahibi olduğun veya yüklemeye yetkili olduğun görselleri yüklemelisin.',
      '• Yasa dışı, hakaret içeren, müstehcen veya başkalarının haklarını ihlal eden içerik yüklememelisin.',
      '• Uygulamayı kötüye kullanmamalı, sistemlerine yetkisiz erişim sağlamaya çalışmamalısın.',
    ]),
    _LegalSection('6. Fikri Mülkiyet', [
      'Uygulamanın kendisi, tasarımı, markası ve yazılımı Evlumba Software\'e aittir.',
      'Yüklediğin görseller sana ait kalır; bunları yalnızca hizmeti sana sunmak amacıyla işleriz. Uygulamanın senin için ürettiği tasarımları kişisel amaçlarla kullanabilirsin.',
    ]),
    _LegalSection('7. Sorumluluğun Sınırlandırılması', [
      'Uygulama "olduğu gibi" sunulur. Hizmetin kesintisiz veya hatasız olacağını ya da yapay zeka çıktılarının belirli bir sonucu garanti edeceğini taahhüt etmeyiz.',
      'Yürürlükteki yasaların izin verdiği ölçüde, uygulamanın kullanımından doğan dolaylı zararlardan sorumlu tutulamayız.',
    ]),
    _LegalSection('8. Fesih ve Askıya Alma', [
      'Bu şartları ihlal etmen halinde hesabını askıya alabilir veya sonlandırabiliriz.',
      'Sen de istediğin zaman hesabını uygulama içinden (Profil > Hesap Yönetimi) silebilirsin. Hesabını silmek, Google Play aboneliğini otomatik olarak iptal ETMEZ; aktif aboneliğini ayrıca Google Play üzerinden iptal etmelisin.',
    ]),
    _LegalSection('9. Değişiklikler', [
      'Bu Kullanım Şartları\'nı zaman zaman güncelleyebiliriz. Önemli değişiklikler uygulama içinde duyurulur. Güncelleme sonrası uygulamayı kullanmaya devam etmen yeni şartları kabul ettiğin anlamına gelir.',
    ]),
    _LegalSection('10. İletişim', [
      'Kullanım Şartları ile ilgili sorular için:',
      '• E-posta: info@evlumba.com',
      '• Geliştirici: Evlumba Software',
    ]),
  ],
);

// ─── KVKK Aydınlatma Metni ─────────────────────────────────────────────
// 6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) m.10 uyarınca
// veri sorumlusunun aydınlatma yükümlülüğü kapsamında hazırlanmıştır.
const _LegalContent _kvkk = _LegalContent(
  title: 'KVKK Aydınlatma Metni',
  updated: '2 Haziran 2026',
  sections: [
    _LegalSection('1. Veri Sorumlusu', [
      'İşbu Aydınlatma Metni, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") m.10 kapsamında, veri sorumlusu sıfatıyla Evlumba Software ("Evlumba", "biz") tarafından, Koala uygulaması ("Uygulama") kullanıcılarını kişisel verilerinin işlenmesine ilişkin bilgilendirmek amacıyla hazırlanmıştır.',
      '• Veri Sorumlusu: Evlumba Software',
      '• İletişim: info@evlumba.com',
    ]),
    _LegalSection('2. İşlenen Kişisel Veriler', [
      'Uygulamayı kullanımına bağlı olarak aşağıdaki kişisel veriler işlenebilir:',
      '• Kimlik ve İletişim Verileri: ad-soyad/görünen ad, e-posta adresi, telefon numarası, profil fotoğrafı.',
      '• Hesap ve Kimlik Doğrulama Verileri: Google/telefon ile giriş bilgileri, kullanıcı kimliği (UID).',
      '• Görsel Veriler: analiz veya paylaşım için yüklediğin mekan ve ilham fotoğrafları.',
      '• İşlem ve Kullanım Verileri: sohbet mesajları, beğeni/kaydetme, tasarım tercihleri, uygulama içi etkileşimler.',
      '• İşlem Güvenliği ve Cihaz Verileri: cihaz türü, işletim sistemi, hata/çökme kayıtları, IP bazlı teknik kayıtlar.',
      '• Abonelik Verileri: satın alma ve abonelik durumu (ödeme kartı bilgileri tarafımızca tutulmaz; Google Play üzerinden işlenir).',
    ]),
    _LegalSection('3. Kişisel Verilerin İşlenme Amaçları', [
      'Kişisel verilerin aşağıdaki amaçlarla işlenir:',
      '• Üyelik oluşturma, kimlik doğrulama ve hesabının yönetilmesi.',
      '• İç mekan analizi, yapay zeka ile tasarım üretimi ve stil keşfi hizmetinin sunulması.',
      '• Tasarımcılarla mesajlaşma ve destek süreçlerinin yürütülmesi.',
      '• Abonelik ve satın alma işlemlerinin yönetilmesi.',
      '• Uygulama performansının ölçülmesi, hata ayıklama ve hizmet kalitesinin artırılması.',
      '• Yasal yükümlülüklerin yerine getirilmesi ve hukuki taleplerin yönetimi.',
    ]),
    _LegalSection('4. İşlemenin Hukuki Sebepleri', [
      'Kişisel verilerin KVKK m.5 kapsamında şu hukuki sebeplere dayanılarak işlenir:',
      '• Bir sözleşmenin kurulması veya ifası için veri işlemenin zorunlu olması (hizmetin sunulması).',
      '• Veri sorumlusunun hukuki yükümlülüğünü yerine getirmesi.',
      '• İlgili kişinin temel hak ve özgürlüklerine zarar vermemek kaydıyla, veri sorumlusunun meşru menfaati.',
      '• Gerektiğinde açık rızanın alınması (örn. isteğe bağlı bildirimler).',
    ]),
    _LegalSection('5. Kişisel Verilerin Aktarılması', [
      'Kişisel verilerin, hizmetin sunulması için gerekli olduğu ölçüde ve KVKK m.8 ve m.9\'a uygun olarak aşağıdaki taraflarla paylaşılabilir:',
      '• Bulut altyapı ve veritabanı sağlayıcıları (Google Firebase, Supabase).',
      '• Yapay zeka işleme hizmeti (Google Gemini).',
      '• Ödeme/abonelik altyapısı (Google Play Billing).',
      '• Yetkili kamu kurum ve kuruluşları (yasal zorunluluk halinde).',
      'Bu sağlayıcıların bir kısmının sunucuları yurt dışında bulunabildiğinden, veriler gerekli güvenlik tedbirleri ve mevzuata uygunluk sağlanarak yurt dışına aktarılabilir.',
    ]),
    _LegalSection('6. Veri Toplama Yöntemi', [
      'Kişisel veriler; uygulamaya kayıt, giriş, görsel yükleme, mesajlaşma ve uygulama içi etkileşimlerin gerçekleştirilmesi yoluyla, elektronik ortamda otomatik ve kısmen otomatik yöntemlerle toplanır.',
    ]),
    _LegalSection('7. Saklama Süresi', [
      'Kişisel veriler, işleme amacının gerektirdiği süre boyunca ve ilgili mevzuatta öngörülen zamanaşımı/saklama süreleri kadar saklanır. Sürenin sonunda veriler silinir, yok edilir veya anonim hale getirilir.',
      'Hesabını sildiğinde, mevzuatın saklamayı zorunlu kıldığı haller dışında verilerin silinir.',
    ]),
    _LegalSection('8. İlgili Kişinin Hakları (KVKK m.11)', [
      'KVKK m.11 uyarınca aşağıdaki haklara sahipsin:',
      '• Kişisel verilerinin işlenip işlenmediğini öğrenme.',
      '• İşlenmişse buna ilişkin bilgi talep etme.',
      '• İşlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme.',
      '• Yurt içinde/dışında aktarıldığı üçüncü kişileri bilme.',
      '• Eksik veya yanlış işlenmişse düzeltilmesini isteme.',
      '• KVKK\'da öngörülen şartlarda silinmesini veya yok edilmesini isteme.',
      '• Düzeltme/silme işlemlerinin aktarılan üçüncü kişilere bildirilmesini isteme.',
      '• Münhasıran otomatik sistemlerle analiz sonucu aleyhine bir sonucun ortaya çıkmasına itiraz etme.',
      '• Hukuka aykırı işleme nedeniyle zarara uğraman halinde zararın giderilmesini talep etme.',
    ]),
    _LegalSection('9. Başvuru Yöntemi', [
      'Yukarıdaki haklarına ilişkin taleplerini info@evlumba.com adresine e-posta göndererek iletebilirsin. Başvurun, talebin niteliğine göre en kısa sürede ve en geç 30 gün içinde ücretsiz olarak sonuçlandırılır; işlemin ayrıca bir maliyet gerektirmesi halinde Kurul tarafından belirlenen tarife uygulanabilir.',
      'Profil > Hesap Yönetimi bölümünden hesabını ve verilerini silmeyi de talep edebilirsin.',
    ]),
    _LegalSection('10. İletişim', [
      '• Veri Sorumlusu: Evlumba Software',
      '• E-posta: info@evlumba.com',
    ]),
  ],
);
