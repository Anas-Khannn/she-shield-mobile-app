import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/health_controller.dart';
import '../utils/app_colors.dart';

/// Shows a small banner while the backend API is unreachable.
///
/// The rest of the UI stays usable — this is just a degraded-mode indicator.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  @override
  void initState() {
    super.initState();
    context.read<HealthController>().checkHealth();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HealthController>();
    if (controller.isReachable) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: Colors.orange.withAlpha(40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 16, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'You are offline. Some features may not work.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}