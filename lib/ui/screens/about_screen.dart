import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/ui_actions.dart';
import '../widgets/common.dart';

/// About: identity, version, credits and the open-source licence entry point.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  static final Uri _repo = Uri.parse(
    'https://github.com/mubazieric/Apple_File_Converter',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _info = info);
      }
    } catch (_) {
      // Version info is best-effort.
    }
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showMessage(context, 'Could not open the link.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.largeAll,
                    gradient: LinearGradient(
                      colors: <Color>[context.colors.primary, AppColors.violet],
                    ),
                  ),
                  child: const Icon(
                    Icons.change_circle_outlined,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Apple File Converter',
                  style: context.text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  info == null
                      ? 'Version unavailable'
                      : 'Version ${info.version} (build ${info.buildNumber})',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Developed by Iwat Digital',
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('What it does', style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Apple File Converter converts, compresses and prepares your '
                  'photos and videos. It handles Apple formats such as HEIC, '
                  'HEIF and MOV alongside everyday formats like JPEG, PNG, WebP, '
                  'MP4, MKV and WebM. Everything is processed on your device: '
                  'your media is never uploaded.',
                  style: context.text.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Open-source licences'),
                  subtitle: const Text(
                    'Flutter, FFmpeg Kit (LGPL), photo_manager and more',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Apple File Converter',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy & data guide'),
                  subtitle: Text(_repo.host),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(_repo),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text('Support & issue tracker'),
                  subtitle: Text(_repo.host),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(Uri.parse('${_repo.toString()}/issues')),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const InfoBanner(
            message:
                'Iwat Digital is the developer credited in the app. No postal '
                'address, phone number or company registration is published here '
                'because none was provided.',
          ),
        ],
      ),
    );
  }
}
