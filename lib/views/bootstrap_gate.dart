import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/health_controller.dart';
import '../services/bootstrap/app_bootstrap.dart';
import '../services/errors/app_exception.dart';
import 'login_view.dart';

/// Runs application initialization and mounts the real UI only afterwards.
///
/// Initialization failures are shown on a dedicated retry screen instead of
/// crashing the app with an uncaught exception.
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key, this.bootstrap});

  /// Injectable for tests. When null, the real [AppBootstrap] is used.
  final Future<void> Function()? bootstrap;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  late Future<void> _bootstrapFuture;
  final _bootstrap = AppBootstrap();

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _runBootstrap();
  }

  Future<void> _runBootstrap() {
    final custom = widget.bootstrap;
    return custom != null ? custom() : _bootstrap.initialize();
  }

  void _retry() {
    setState(() {
      _bootstrapFuture = _runBootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BootstrapSplash();
        }
        if (snapshot.hasError) {
          return _BootstrapErrorView(
            error: snapshot.error,
            onRetry: _retry,
          );
        }
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthController()),
            ChangeNotifierProvider(create: (_) => HealthController()),
          ],
          child: const LoginView(),
        );
      },
    );
  }
}

class _BootstrapSplash extends StatelessWidget {
  const _BootstrapSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _BootstrapErrorView extends StatelessWidget {
  const _BootstrapErrorView({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final message = error is AppException
        ? error.userMessage
        : 'The app could not start. Please try again.';

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}