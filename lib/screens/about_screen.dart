import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  /// App version from the platform (pubspec `version:`), e.g. "1.0.0".
  /// Shows "—" until/unless the package plugin can report it.
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _version = info.version;
      });
    } catch (_) {
      // Plugin unavailable (e.g. widget tests): leave the "—" placeholder.
    }
  }

  Future<void> _openWiki() async {
    final url = Uri.parse('https://oldschool.runescape.wiki');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // No-op: the app will still show the screen even if the browser cannot open.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'GE Prices',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Version ${_version ?? '—'}',
              style: const TextStyle(
                color: AppTheme.secondaryTextColor,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'A lightweight Grand Exchange price tracker for Old School RuneScape, using live item and market data from the RuneScape Wiki.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            InkWell(
              onTap: _openWiki,
              child: const Text(
                'oldschool.runescape.wiki',
                style: TextStyle(
                  color: AppTheme.accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Created using intellectual property belonging to Jagex Limited '
              "under the terms of Jagex's Fan Content Policy. This content is "
              'not endorsed by or affiliated with Jagex.',
              style: TextStyle(
                color: AppTheme.secondaryTextColor,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'RuneScape and Old School RuneScape are trademarks of Jagex Ltd. '
              'Price and item data courtesy of the OSRS Wiki, licensed '
              'CC BY-NC-SA 3.0.',
              style: TextStyle(
                color: AppTheme.secondaryTextColor,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}