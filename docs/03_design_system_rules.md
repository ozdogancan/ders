# Design System Rules - Koala Project

## Renk Paleti

Tum renkler theme uzerinden erisilmeli. Hardcoded Color() YASAK.

```dart
// DOGRU
Theme.of(context).colorScheme.primary

// YANLIS
Color(0xFF6C63FF)
```

### Ana Renkler
- **Primary:** Koala moru/mavi tonu
- **Secondary:** Vurgulama rengi
- **Surface:** Kart/container arka plani
- **Error:** Hata durumu kirmizi
- **OnPrimary/OnSurface:** Metin renkleri

## Typography

Tum text style'lar TextTheme uzerinden kullanilmali.

```dart
// DOGRU
Theme.of(context).textTheme.headlineMedium
Theme.of(context).textTheme.bodyLarge

// YANLIS
TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
```

### Hiyerarsi
| Kullanim | TextTheme |
|----------|-----------|
| Sayfa basligi | headlineMedium |
| Section basligi | titleLarge |
| Kart basligi | titleMedium |
| Normal metin | bodyLarge |
| Kucuk metin | bodyMedium |
| Caption/etiket | labelSmall |

## Spacing Sistemi

4px grid kullan. Kabul edilen degerler:

| Token | Deger | Kullanim |
|-------|-------|----------|
| xs | 4 | Icon-text arasi |
| sm | 8 | Kart ici oge arasi |
| md | 12 | Section ici oge arasi |
| lg | 16 | Kart padding, section arasi |
| xl | 24 | Buyuk bolum arasi |
| xxl | 32 | Sayfa ust/alt padding |

```dart
// DOGRU
const EdgeInsets.all(16)
const SizedBox(height: 8)

// YANLIS
const EdgeInsets.all(13)
const SizedBox(height: 7)
```

## Border Radius

| Kullanim | Radius |
|----------|--------|
| Buton | 12 |
| Kart | 16 |
| Input field | 12 |
| Bottom sheet | 24 (ust) |
| Avatar | CircleBorder |
| Chip/tag | 20 |

## Canonical Widget'lar

### KoalaButton
```dart
KoalaButton(
  label: 'Ders Al',
  onPressed: () {},
  variant: ButtonVariant.primary,  // primary, secondary, text
  isLoading: false,
  isFullWidth: true,
)
```

### KoalaCard
```dart
KoalaCard(
  child: ...,
  padding: EdgeInsets.all(16),
  onTap: () {},  // opsiyonel
)
```

### KoalaTextField
```dart
KoalaTextField(
  label: 'Email',
  hint: 'ornek@email.com',
  controller: _emailController,
  validator: (v) => v.isEmpty ? 'Zorunlu alan' : null,
  keyboardType: TextInputType.emailAddress,
)
```

### LoadingState (MEVCUT - lib/widgets/loading_state.dart)
```dart
LoadingState(
  message: 'Yukleliyor...',  // opsiyonel
)
```

### ErrorState (MEVCUT - lib/widgets/error_state.dart)
```dart
ErrorState(
  message: 'Bir hata olustu',
  onRetry: () {},
)
```

### ErrorView (MEVCUT - lib/widgets/error_view.dart)
```dart
ErrorView.network(onRetry: () {})  // Baglanti hatasi
ErrorView.server(onRetry: () {})   // Sunucu hatasi
ErrorView.timeout(onRetry: () {})  // Zaman asimi
```

### EmptyState (MEVCUT - lib/widgets/empty_state.dart)
```dart
EmptyState(
  icon: Icons.school_outlined,
  title: 'Henuz dersiniz yok',
  description: 'Ders aramaya baslayin',
  buttonText: 'Ders Ara',
  onButtonTap: () {},
)
```

### ShimmerList / ShimmerGrid (MEVCUT - lib/widgets/shimmer_loading.dart)
```dart
ShimmerList(itemCount: 4, cardHeight: 80)   // Liste loading
ShimmerGrid(itemCount: 4, crossAxisCount: 2) // Grid loading
```

### Barrel Import
```dart
import '../widgets/koala_widgets.dart';  // Tum canonical widget'lar

```

## Ekran Yapisi Sablonu

Her yeni ekran su yapiyi takip etmeli:

```dart
class XxxScreen extends StatefulWidget {  // veya ConsumerWidget
  const XxxScreen({super.key});

  @override
  State<XxxScreen> createState() => _XxxScreenState();
}

class _XxxScreenState extends State<XxxScreen> {
  // State degiskenleri
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // veri cek
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Baslik')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return KoalaLoadingState();
    if (_error != null) return KoalaErrorState(message: _error!, onRetry: _loadData);
    // normal icerik
  }
}
```

## Icon Kullanimi

- Material Icons kullan (Icons.xxx)
- Outlined varyant tercih et (Icons.xxx_outlined)
- Icon size: 20 (kucuk), 24 (normal), 32 (buyuk)

## Image/Avatar

- Profil resmi: CircleAvatar, radius 24 (kucuk), 40 (orta), 60 (buyuk)
- Placeholder: Bos avatar icin baslangic harfi goster
- Network image: CachedNetworkImage kullan (varsa)
