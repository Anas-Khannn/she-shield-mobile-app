import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sos_status.dart';
import '../services/sos_coordinator.dart';
import '../utils/app_colors.dart';
import '../widgets/sos_status_sheet.dart';

class SafetyTimerView extends StatefulWidget {
  const SafetyTimerView({super.key});

  @override
  State<SafetyTimerView> createState() => _SafetyTimerViewState();
}

class _SafetyTimerViewState extends State<SafetyTimerView> {
  final _coordinator = SOSCoordinator();

  int _secondsRemaining = 0;
  Timer? _timer;
  bool _isRunning = false;
  bool _sosTriggering = false;

  void _startTimer(int seconds) {
    setState(() {
      _secondsRemaining = seconds;
      _isRunning = true;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
        _triggerSos();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _secondsRemaining = 0;
    });
  }

  Future<void> _triggerSos() async {
    if (_sosTriggering) return;
    setState(() {
      _isRunning = false;
      _sosTriggering = true;
    });
    final status = await _coordinator.triggerSos();
    if (!mounted) return;
    setState(() => _sosTriggering = false);
    _showStatusSheet(status);
  }

  void _showStatusSheet(SosStatus status) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SosStatusSheet(
        statusListenable: ValueNotifier<SosStatus>(status),
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Timer')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isRunning ? 'SOS triggers in' : 'Set Safety Timer',
                  style: const TextStyle(
                    fontSize: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _sosTriggering
                      ? '…'
                      : _isRunning
                          ? '$_secondsRemaining'
                          : '--',
                  style: const TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 40),
                if (_sosTriggering)
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                else if (!_isRunning) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _timerOption(60, '1 Min'),
                      _timerOption(300, '5 Min'),
                      _timerOption(600, '10 Min'),
                    ],
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: _stopTimer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('I AM SAFE - CANCEL'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timerOption(int seconds, String label) {
    return InkWell(
      onTap: () => _startTimer(seconds),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label),
      ),
    );
  }
}