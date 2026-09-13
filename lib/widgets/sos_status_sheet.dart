import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:she_shield/models/sos_status.dart';
import 'package:she_shield/utils/app_colors.dart';
import 'package:she_shield/utils/app_dimens.dart';

/// Bottom sheet that reports the status of every SOS operation individually.
///
/// A partial failure (for example GPS unavailable while the call still went
/// through) is shown as exactly that — individual check/cross rows — never as
/// a misleading global "success" screen.
///
/// The panel observes [statusListenable] so individual rows update live as
/// each operation finishes. Pass the *same* [ValueNotifier] instance that the
/// running SOS controller writes to.
class SosStatusSheet extends StatelessWidget {
  const SosStatusSheet({
    super.key,
    required this.statusListenable,
    this.onRetry,
    this.onClose,
  });

  final ValueListenable<SosStatus> statusListenable;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.lg,
          AppDimens.md,
          AppDimens.lg,
          AppDimens.lg,
        ),
        child: ValueListenableBuilder<SosStatus>(
          valueListenable: statusListenable,
          builder: (context, status, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [..._content(status, context)],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(SosStatus status, BuildContext context) {
    final allSucceeded = status.allSucceeded;
    final anyFailed = status.anyFailed;

    return [
      _handle(),
      const SizedBox(height: AppDimens.md),
      _Header(status: status),
      const SizedBox(height: AppDimens.md),
      _OperationList(status: status),
      const SizedBox(height: AppDimens.md),
      if (allSucceeded) ..._successBanner(),
      if (anyFailed) ...[
        const SizedBox(height: AppDimens.md),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('RETRY FAILED STEPS'),
        ),
      ],
      if (onClose != null) ...[
        const SizedBox(height: AppDimens.sm),
        OutlinedButton(
          onPressed: onClose,
          child: const Text('CLOSE'),
        ),
      ],
    ];
  }

  Widget _handle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textMuted,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  List<Widget> _successBanner() {
    return [
      Container(
        padding: const EdgeInsets.all(AppDimens.md),
        decoration: BoxDecoration(
          color: AppColors.success.withAlpha(30),
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          border: Border.all(color: AppColors.success.withAlpha(80)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.success),
            SizedBox(width: AppDimens.sm),
            Expanded(
              child: Text(
                'All safety actions completed.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status});

  final SosStatus status;

  @override
  Widget build(BuildContext context) {
    final complete = status.isFinished;
    final anyFailed = status.anyFailed;

    final (String title, Color color, IconData icon) = !complete
        ? ('SOS in progress…', AppColors.accent, Icons.emergency_share)
        : anyFailed
            ? (
                'SOS partially completed',
                AppColors.warning,
                Icons.warning_amber_rounded,
              )
            : (
                'SOS sent successfully',
                AppColors.success,
                Icons.check_circle_outline,
              );

    return Row(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(width: AppDimens.sm),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '${status.finishedCount}/${SosOperation.values.length}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      ],
    );
  }
}

class _OperationList extends StatelessWidget {
  const _OperationList({required this.status});

  final SosStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < SosOperation.values.length; index++) ...[
          if (index > 0) const SizedBox(height: AppDimens.sm),
          _OperationRow(
            operation: SosOperation.values[index],
            result: status.resultOf(SosOperation.values[index]),
          ),
        ],
      ],
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({required this.operation, required this.result});

  final SosOperation operation;
  final SosOperationResult result;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String semantic) =
        switch (result.state) {
      SosOperationState.success => (
          Icons.check_circle,
          AppColors.success,
          '${operation.label} succeeded',
        ),
      SosOperationState.failure => (
          Icons.cancel,
          Colors.redAccent,
          '${operation.label} failed',
        ),
      SosOperationState.running => (
          Icons.autorenew,
          AppColors.accent,
          '${operation.label} running',
        ),
      SosOperationState.pending => (
          Icons.circle_outlined,
          AppColors.textMuted,
          '${operation.label} pending',
        ),
    };

    return Semantics(
      container: true,
      label: semantic,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.md,
          vertical: AppDimens.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        child: Row(
          children: [
            if (result.state == SosOperationState.running)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: color,
                ),
              )
            else
              Icon(icon, color: color, size: 22),
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
                      fontSize: 15,
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
        ),
      ),
    );
  }
}