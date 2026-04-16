/// Ortak formatlama yardımcıları

/// Supabase TIMESTAMPTZ UTC ISO string döner; .hour/.minute UTC verir.
/// Mesaj baloncuğu gibi "HH:MM" gösterimler için her zaman lokale çevir.
String formatHM(DateTime dt) {
  final local = dt.isUtc ? dt.toLocal() : dt;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// "DD/MM HH:MM" (admin/log ekranlarında)
String formatDMHM(DateTime dt) {
  final local = dt.isUtc ? dt.toLocal() : dt;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month} $hh:$mm';
}

/// "DD/MM/YYYY HH:MM" (admin tabloları)
String formatDMYHM(DateTime dt) {
  final local = dt.isUtc ? dt.toLocal() : dt;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} $hh:$mm';
}

String timeAgo(DateTime dt) {
  // Supabase TIMESTAMPTZ degerleri UTC doner; karsilastirmak icin
  // DateTime.now()'u da UTC'ye cevir. Yoksa timezone offset kadar
  // negatif diff olusup "Simdi" takiliyor (ornek: TR saatiyle
  // gonderilmis ama offset suffix'siz yazilmis eski satirlar).
  final nowUtc = DateTime.now().toUtc();
  final dtUtc = dt.isUtc ? dt : dt.toUtc();
  final diff = nowUtc.difference(dtUtc);
  // Saat kaymasi / ileri tarih → guvenli sekilde "Simdi"
  if (diff.isNegative) return 'Şimdi';
  if (diff.inMinutes < 1) return 'Şimdi';
  if (diff.inHours < 1) return '${diff.inMinutes}dk';
  if (diff.inDays < 1) return '${diff.inHours}sa';
  if (diff.inDays < 7) return '${diff.inDays}g';
  final local = dt.isUtc ? dt.toLocal() : dt;
  return '${local.day}/${local.month}';
}
