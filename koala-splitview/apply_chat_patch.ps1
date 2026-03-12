## chat_screen.dart PATCH Script
## PowerShell'de çalıştır: Bu script chat_screen.dart'ta 4 küçük değişiklik yapar
## Önce backup alır!

$file = "lib/views/chat_screen.dart"
$backup = "lib/views/chat_screen.dart.bak"

# Backup
Copy-Item $file $backup -Force
Write-Host "Backup alindi: $backup" -ForegroundColor Green

$content = Get-Content $file -Raw -Encoding UTF8

# PATCH 1: Constructor - embedded ve onCreditsChanged ekle
$content = $content -replace `
  'const ChatScreen\(\{super\.key, required this\.questionId\}\);\s*\n\s*final String questionId;', `
  "const ChatScreen({super.key, required this.questionId, this.embedded = false, this.onCreditsChanged});`n  final String questionId;`n  final bool embedded;`n  final VoidCallback? onCreditsChanged;"

# PATCH 2: _loadCredits callback
$content = $content -replace `
  '(Future<void> _loadCredits\(\) async \{\s*\n\s*final c = await _credit\.getCredits\(\);\s*\n\s*if \(mounted\) setState\(\(\) => _credits = c\);\s*\n\s*\})', `
  "Future<void> _loadCredits() async {`n    final c = await _credit.getCredits();`n    if (mounted) setState(() => _credits = c);`n    widget.onCreditsChanged?.call();`n  }"

# PATCH 3: Back button - embedded modda gizle
$content = $content -replace `
  "leading: IconButton\(onPressed: \(\) => Navigator\.pop\(context\),\s*\n\s*icon: const Icon\(Icons\.arrow_back_rounded, color: Color\(0xFF1E293B\)\)\),", `
  "leading: widget.embedded ? const SizedBox(width: 16) : IconButton(onPressed: () => Navigator.pop(context),`n          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B))),"

# PATCH 4: Swipe-to-go-back - embedded modda devre disi birak
$content = $content -replace `
  'onHorizontalDragEnd: \(details\) \{', `
  'onHorizontalDragEnd: widget.embedded ? null : (details) {'

Set-Content $file $content -Encoding UTF8 -NoNewline
Write-Host "chat_screen.dart guncellendi!" -ForegroundColor Green
Write-Host "4 patch uygulandi." -ForegroundColor Cyan
