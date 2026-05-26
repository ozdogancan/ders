// Horizontal PageView between designs — Instagram-detail pattern.
// Tap from grid → opens here at the tapped index, Hero on the first frame.
// Subsequent swipes are smooth PageView transitions (no Hero re-trigger).

import 'package:flutter/material.dart';
import '../my_designs/design_detail_screen.dart';

class ProfileDesignSwipeScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  const ProfileDesignSwipeScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<ProfileDesignSwipeScreen> createState() =>
      _ProfileDesignSwipeScreenState();
}

class _ProfileDesignSwipeScreenState extends State<ProfileDesignSwipeScreen> {
  late final PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _ctrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.items.length,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          // DesignDetailScreen does Hero('design-${item['id']}'); we wrap
          // only the active page so PageView swipes don't fight Hero.
          return DesignDetailScreen(item: widget.items[i]);
        },
      ),
    );
  }
}
