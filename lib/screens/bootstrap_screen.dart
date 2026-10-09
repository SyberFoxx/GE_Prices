import 'package:flutter/material.dart';

import '../services/osrs_api.dart';
import '../theme/app_theme.dart';
import '../widgets/skeletons.dart';
import 'home_screen.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  final OsrsApi _api = OsrsApi();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStartupData();
  }

  Future<void> _loadStartupData() async {
    try {
      final mappingRequest = _api.fetchItemMapping();
      final latestRequest = _api.fetchLatestPrices();
      final items = await mappingRequest;
      final latest = await latestRequest;

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
        _errorMessage = 'No internet connection';
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      _errorMessage = null;
    });
    await _loadStartupData();
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
                    if (_errorMessage == null) ...<Widget>[
                      const ItemRowSkeleton(),
                      const ItemRowSkeleton(),
                      const ItemRowSkeleton(),
                    ] else ...<Widget>[
                      const Icon(
                        Icons.wifi_off_rounded,
                        color: AppTheme.secondaryTextColor,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Check your connection and try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.secondaryTextColor),
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
