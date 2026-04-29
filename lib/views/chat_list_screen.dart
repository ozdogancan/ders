import 'package:flutter/material.dart';

import 'chat_list_screen_v1.dart';
import 'chat_list_screen_v2.dart';

const bool kUseChatListV2 = false;

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return kUseChatListV2 ? const ChatListScreenV2() : const ChatListScreenV1();
  }
}
