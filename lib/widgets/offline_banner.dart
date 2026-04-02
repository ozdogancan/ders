import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

/// Compact offline banner — shows when device has no internet.
/// Place at the top of any screen body with Column([OfflineBanner(), Expanded(...)]).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.status,
      builder: (context, isOnline, _) {
        if (isOnline) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xFFFFF7ED),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, size: 18, color: Color(0xFFEA580C)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Bağlantı yok — çevrimdışı moddasın',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9A3412), fontWeight: FontWeight.w500),
                ),
              ),
              GestureDetector(
                onTap: () => ConnectivityService.check(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: const Text(
                    'Tekrar Dene',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEA580C)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
