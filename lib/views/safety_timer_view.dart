import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/safety_timer_controller.dart';
import '../models/safety_timer_state.dart';
import '../models/sos_status.dart';
import '../utils/app_colors.dart';
import '../utils/app_dimens.dart';

/// Safety timer screen backed by [SafetyTimerController].
///
/// The controller is the single source of truth — this view owns no timer
/// logic. An optional [controller] parameter allows tests to inject a fake
/// without going through Provider.
class SafetyTimerView extends StatelessWidget {
  const SafetyTimerView({super.key, this.controller});

  /// When non-null, used instead of `context.watch<SafetyTimerController>()`.
  /// This is only for testing — production always uses Provider.
  final SafetyTimerController? controller;

  @override
  Widget build(BuildContext context) {
    final ctrl =
        controller ?? context.watch<SafetyTimerController>();
    return _SafetyTimerBody(controller: ctrl);
  }
}

class _SafetyTimerBody extends StatelessWidget {
  const _SafetyTimerBody({required this.controller});

  final SafetyTimerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Timer')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.lg),
            child: _TimerContent(controller: controller),
          ),
        ),
      ),
    );
  }
}

class _TimerContent extends StatelessWidget {
  const _TimerContent({required this.controller});

  final SafetyTimerController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Header label ──────────────────────────────────────────────
        Text(
          _headerText(status),
          style: const TextStyle(
            fontSize: 20,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimens.lg),

        // ── Countdown / placeholder ──────────────────────────────────
        if (status == SafetyTimerStatus.running)
          Text(
            controller.remainingFormatted,
            key: const Key('countdown'),
            style: const TextStyle(
              fontSize: 80,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          )
        else if (status == SafetyTimerStatus.idle ||
            status == SafetyTimerStatus.cancelled)
          const Text(
            '--',
            style: TextStyle(
              fontSize: 80,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          )
        else if (status == SafetyTimerStatus.expired ||
            status == SafetyTimerStatus.failed)
          Icon(
            status == SafetyTimerStatus.expired
                ? Icons.check_circle_outline
                : Icons.error_outline,
            size: 80,
            color: status == SafetyTimerStatus.expired
                ? AppColors.success
                : AppColors.warning,
          ),

        const SizedBox(height: AppDimens.xxl),

        // ── Action area ──────────────────────────────────────────────
        if (controller.errorMessage != null &&
            controller.errorMessage!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.md),
            child: Text(
              controller.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.warning, fontSize: 14),
            ),
          ),
        ],

        ..._actionArea(context, controller),
      ],
    );
  }

  String _headerText(SafetyTimerStatus status) {
    return switch (status) {
      SafetyTimerStatus.idle => 'Set Safety Timer',
      SafetyTimerStatus.running => 'SOS triggers in',
      SafetyTimerStatus.expired => 'SOS Activated',
      SafetyTimerStatus.cancelled => 'Set Safety Timer',
      SafetyTimerStatus.failed => 'SOS Failed',
    };
  }

  List<Widget> _actionArea(BuildContext context, SafetyTimerController ctrl) {
    switch (ctrl.status) {
      case SafetyTimerStatus.idle:
      case SafetyTimerStatus.cancelled:
        return [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _DurationChip(label: '1 Min', duration: const Duration(minutes: 1), controller: ctrl),
              _DurationChip(label: '5 Min', duration: const Duration(minutes: 5), controller: ctrl),
              _DurationChip(label: '10 Min', duration: const Duration(minutes: 10), controller: ctrl),
            ],
          ),
        ];

      case SafetyTimerStatus.running:
        return [
          ElevatedButton(
            onPressed: ctrl.cancel,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: const Text('I AM SAFE - CANCEL'),
          ),
        ];

      case SafetyTimerStatus.expired:
      case SafetyTimerStatus.failed:
        return [
          if (ctrl.lastSosStatus != null)
            _InlineSosSummary(status: ctrl.lastSosStatus!),
          if (ctrl.lastSosStatus != null)
            const SizedBox(height: AppDimens.md),
          OutlinedButton(
            onPressed: ctrl.reset,
            child: const Text('BACK'),
          ),
        ];
    }
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.duration,
    required this.controller,
  });

  final String label;
  final Duration duration;
  final SafetyTimerController controller;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => controller.start(duration),
      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.lg,
          vertical: AppDimens.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Inline per-action summary shown after expiration — reuses the same
/// data model as the bottom sheet but without the modal overlay.
class _InlineSosSummary extends StatelessWidget {
  const _InlineSosSummary({required this.status});

  final SosStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final op in SosOperation.values) ...[
            _InlineOperationRow(
              operation: op,
              result: status.resultOf(op),
            ),
            if (op != SosOperation.values.last)
              const SizedBox(height: AppDimens.sm),
          ],
        ],
      ),
    );
  }
}

class _InlineOperationRow extends StatelessWidget {
  const _InlineOperationRow({
    required this.operation,
    required this.result,
  });

  final SosOperation operation;
  final SosOperationResult result;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (result.state) {
      SosOperationState.success => (Icons.check_circle, AppColors.success),
      SosOperationState.failure => (Icons.cancel, Colors.redAccent),
      SosOperationState.running => (Icons.autorenew, AppColors.accent),
      SosOperationState.pending => (Icons.circle_outlined, AppColors.textMuted),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppDimens.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                operation.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (result.message != null)
                Text(
                  result.message!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
