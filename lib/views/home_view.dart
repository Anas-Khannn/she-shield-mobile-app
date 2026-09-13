import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:geolocator/geolocator.dart';

import '../controllers/contact_controller.dart';
import '../controllers/sos_controller.dart';
import '../models/contact_model.dart';
import '../models/sos_status.dart';
import '../services/location_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_dimens.dart';
import '../widgets/sos_status_sheet.dart';
import 'fake_call_view.dart';
import 'safety_timer_view.dart';
import 'settings_view.dart';

/// The main landing screen.
///
/// SOS is the primary visual action. The screen also surfaces location
/// readiness, emergency contacts, the safety timer, and the profile — without
/// turning into a wall of features.
class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    this.onNavigateToTab,
    this.fetchLocation,
    this.fetchContacts,
    this.sosController,
  });

  /// Lets the home screen switch the bottom navigation tab (e.g. to Contacts).
  final ValueChanged<int>? onNavigateToTab;

  /// Injectable location lookup so tests can avoid the device plugins.
  final Future<Position?> Function()? fetchLocation;

  /// Injectable emergency-contacts lookup so tests can avoid the device
  /// plugins.
  final Future<List<ContactModel>> Function()? fetchContacts;

  /// Injectable SOS runner so tests can avoid the device plugins.
  final SOSController? sosController;

  @override
  State<HomeView> createState() => _HomeViewState();
}

enum _LocationStatus { checking, ready, failure }

class _HomeViewState extends State<HomeView> {
  late final SOSController _sosController =
      widget.sosController ?? SOSController();
  final _sosStatusNotifier = ValueNotifier<SosStatus>(SosStatus.initial());

  _LocationStatus _locationStatus = _LocationStatus.checking;
  double? _latitude;
  double? _longitude;
  bool _sosRunning = false;
  int _contactCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshLocation();
    _loadContactCount();
  }

  @override
  void dispose() {
    _sosStatusNotifier.dispose();
    super.dispose();
  }

  Future<void> _refreshLocation() async {
    setState(() => _locationStatus = _LocationStatus.checking);
    try {
      final position =
          await (widget.fetchLocation ?? LocationService.getCurrentLocation)();
      if (!mounted) return;
      setState(() {
        if (position != null) {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _locationStatus = _LocationStatus.ready;
        } else {
          _locationStatus = _LocationStatus.failure;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _locationStatus = _LocationStatus.failure);
      }
    }
  }

  Future<void> _loadContactCount() async {
    final contacts = await (widget.fetchContacts ?? ContactController.getContacts)();
    if (mounted) {
      setState(() => _contactCount = contacts.length);
    }
  }

  Future<void> _triggerSos() async {
    if (_sosRunning) return;
    setState(() {
      _sosRunning = true;
      _sosStatusNotifier.value = SosStatus.initial();
    });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimens.radiusLg)),
      ),
      builder: (context) => SosStatusSheet(
        statusListenable: _sosStatusNotifier,
        onRetry: () {
          Navigator.pop(context);
          _triggerSos();
        },
        onClose: () => Navigator.pop(context),
      ),
    );

    final status = await _sosController.triggerSos(
      onStatusChanged: (s) => _sosStatusNotifier.value = s,
    );
    _sosStatusNotifier.value = status;
    if (mounted) {
      setState(() => _sosRunning = false);
    }
  }

  void _showProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsView()),
    );
  }

  void _goToContacts() {
    final onNavigate = widget.onNavigateToTab;
    if (onNavigate != null) {
      onNavigate(1);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SettingsView(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.darkGradient),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    const SizedBox(height: AppDimens.md),
                    _buildHeader(context),
                    const SizedBox(height: AppDimens.lg),
                    _buildLocationCard(context),
                    const SizedBox(height: AppDimens.lg),
                    _buildSosArea(context),
                    const SizedBox(height: AppDimens.lg),
                    _buildContactsCard(context),
                    const SizedBox(height: AppDimens.md),
                    _buildQuickActions(context),
                    const SizedBox(height: AppDimens.lg),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shield Active',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'You are safe',
              style: Theme.of(context).textTheme.displayMedium,
            ),
          ],
        ),
        Tooltip(
          message: 'Account and settings',
          child: IconButton(
            onPressed: _showProfile,
            icon: const CircleAvatar(
              backgroundColor: AppColors.surfaceElevated,
              child: Icon(Icons.person_outline, color: AppColors.textPrimary),
            ),
            tooltip: 'Profile',
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard(BuildContext context) {
    final (IconData icon, Color color, String title, String subtitle) =
        switch (_locationStatus) {
      _LocationStatus.checking => (
          Icons.location_searching,
          AppColors.accent,
          'Checking location…',
          'Confirming your location for SOS',
        ),
      _LocationStatus.ready => (
          Icons.location_on,
          AppColors.success,
          'Location ready',
          _latitude == null
              ? 'GPS signal acquired'
              : '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
        ),
      _LocationStatus.failure => (
          Icons.location_off_outlined,
          Colors.redAccent,
          'Location unavailable',
          'Enable GPS to share your live location in an SOS',
        ),
    };

    return Semantics(
      container: true,
      label: 'Location readiness: $title',
      child: Container(
        padding: const EdgeInsets.all(AppDimens.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            if (_locationStatus == _LocationStatus.checking)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.accent,
                ),
              )
            else
              Icon(icon, color: color, size: 26),
            const SizedBox(width: AppDimens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _refreshLocation,
              icon: _locationStatus == _LocationStatus.checking
                  ? const SizedBox.shrink()
                  : const Icon(Icons.refresh, size: 20, color: AppColors.accent),
              tooltip: 'Refresh location',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSosArea(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final maxSize = constraints.maxWidth * 0.6;
            final size = maxSize.clamp(130.0, 210.0);
            return _SosButton(
              size: size,
              running: _sosRunning,
              onPressed: _triggerSos,
            );
          },
        ),
        const SizedBox(height: AppDimens.md),
        FadeInUp(
          child: Text(
            _sosRunning ? 'ALERT IN PROGRESS' : 'TAP TO ALERT CONTACTS',
            style: TextStyle(
              color: _sosRunning ? AppColors.primary : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactsCard(BuildContext context) {
    final count = _contactCount;
    final hasContacts = count > 0;

    return Semantics(
      container: true,
      button: true,
      label: hasContacts
          ? '$count emergency contacts set up. Tap to manage.'
          : 'No emergency contacts set up. Tap to add.',
      child: InkWell(
        onTap: _goToContacts,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppDimens.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasContacts
                      ? AppColors.accent.withAlpha(25)
                      : AppColors.warning.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.people_outline,
                  color: hasContacts ? AppColors.accent : AppColors.warning,
                ),
              ),
              const SizedBox(width: AppDimens.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasContacts
                          ? '$count Emergency Contact${count == 1 ? '' : 's'}'
                          : 'No Emergency Contacts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      hasContacts
                          ? 'Tap to manage your trusted contacts'
                          : 'Add contacts to alert during an SOS',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.timer_outlined,
            label: 'Safety Timer',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SafetyTimerView()),
              );
            },
          ),
        ),
        const SizedBox(width: AppDimens.md),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.call_outlined,
            label: 'Fake Call',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FakeCallView()),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SosButton extends StatefulWidget {
  const _SosButton({
    required this.size,
    required this.running,
    required this.onPressed,
  });

  final double size;
  final bool running;
  final VoidCallback onPressed;

  @override
  State<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<_SosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      lowerBound: 0.94,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Emergency SOS button, tap to alert contacts',
      button: true,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.running ? 1.0 : _pulse.value,
            child: child,
          );
        },
        child: GestureDetector(
          onTap: widget.running ? null : widget.onPressed,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.sosGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(110),
                  blurRadius: 34,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'SOS',
                    style: TextStyle(
                      fontSize: widget.size * 0.28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppDimens.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.accent, size: 30),
              const SizedBox(height: AppDimens.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}