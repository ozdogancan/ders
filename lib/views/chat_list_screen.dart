import 'package:flutter/material.dart';

import 'chat_list_screen_v1.dart';
import 'chat_list_screen_v2.dart';

// ═══════════════════════════════════════════════════════════════════
// Mesajlar ekranı — versiyon anahtarı
// ─────────────────────────────────────────────────────────────────
// v1 (arşiv): mor gradient hero + yığılı sections — chat_list_screen_v1.dart
// v2 (aktif): "Editorial Warmth" — chat_list_screen_v2.dart
//
// Rollback için tek satır: aşağıdaki `kUseChatListV2` → false.
// ═══════════════════════════════════════════════════════════════════
const bool kUseChatListV2 = false;

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return kUseChatListV2 ? const ChatListScreenV2() : const ChatListScreenV1();
  }
}
