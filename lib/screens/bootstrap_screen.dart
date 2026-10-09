import 'package:flutter/material.dart';

import '../services/osrs_api.dart';
import '../theme/app_theme.dart';
import '../utils/fetch_errors.dart';
import '../widgets/skeletons.dart';
import 'home_screen.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  final OsrsApi _api = OsrsApi();
  FetchErrorInfo? _error;

  @override
  void initState() {
    super.initState();
    _loadStartupData();
  }

  Future<void> _loadStartupData() async {
    try {
      // Wait for both in parallel. Using a parallel wait (instead of awaiting
      // one then the other) guarantees both futures have an error handler, so a
      // failing /mapping can never leave /latest as an unhandled async error.
      final (items, latest) = await (
        _api.fetchItemMapping(),
        _api.fetchLatestPrices(),
      ).wait;

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              HomeScreen(initialItems: items, initialLatestPrices: latest.data),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = describeFetchError(error);
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
    });
    await _loadStartupData();
  }

  IconData _errorIcon(FetchErrorKind kind) {
    switch (kind) {
      case FetchErrorKind.network:
        return Icons.wifi_off_rounded;
      case FetchErrorKind.server:
        return Icons.cloud_off_rounded;
      case FetchErrorKind.format:
        return Icons.sync_problem_rounded;
      case FetchErrorKind.unknown:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Image.asset(
                      'assets/icon.png',
                      width: 112,
                      height: 112,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 24),
                    if (_error == null) ...<Widget>[
                      const ItemRowSkeleton(),
                      const ItemRowSkeleton(),
                      const ItemRowSkeleton(),
                    ] else ...<Widget>[
                      Icon(
                        _errorIcon(_error!.kind),
                        color: AppTheme.secondaryTextColor,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _error!.hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}