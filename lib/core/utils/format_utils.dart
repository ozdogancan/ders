/// Ortak formatlama yardımcıları
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
