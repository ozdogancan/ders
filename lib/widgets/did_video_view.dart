import 'package:flutter/material.dart';

class DidVideoView extends StatefulWidget {
  const DidVideoView({
    super.key,
    required this.videoUrl,
    this.onEnded,
  });

  final String videoUrl;
  final VoidCallback? onEnded;

  @override
  State<DidVideoView> createState() => _DidVideoViewState();
}

class _DidVideoViewState extends State<DidVideoView> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Video yukleniyor...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onEnded,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 64),
              const SizedBox(height: 16),
              Text('Video hazir', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              Text('Kapatmak icin dokun', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}
