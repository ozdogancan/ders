/// Ortak formatlama yardımcıları
String timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Şimdi';
  if (diff.inHours < 1) return '${diff.inMinutes}dk';
  if (diff.inDays < 1) return '${diff.inHours}sa';
  if (diff.inDays < 7) return '${diff.inDays}g';
  return '${dt.day}/${dt.month}';
}
