import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/cinemahub_colors.dart';
import '../theme/cinemahub_tokens.dart';

/// Information regarding an available OTA update.
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String apkDownloadUrl;
  final String releaseUrl;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.releaseUrl,
    required this.hasUpdate,
  });
}

/// Service handling Over-The-Air (OTA) updates by querying GitHub Releases.
class UpdateService extends ChangeNotifier {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  bool _checking = false;
  bool get checking => _checking;

  UpdateInfo? _latestUpdate;
  UpdateInfo? get latestUpdate => _latestUpdate;

  /// Check GitHub releases for an update.
  Future<UpdateInfo?> checkForUpdate({String repo = 'nadeemalam178/cinemahub'}) async {
    _checking = true;
    notifyListeners();

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await _dio.get(
        'https://api.github.com/repos/$repo/releases/latest',
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'CinemaHub-App',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        _checking = false;
        notifyListeners();
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final rawTag = (data['tag_name'] as String? ?? '').replaceFirst('v', '').trim();
      final releaseNotes = data['body'] as String? ?? 'A new version of CinemaHub is available.';
      final releaseUrl = data['html_url'] as String? ?? 'https://github.com/$repo/releases';

      // Find the direct APK asset URL
      String apkUrl = releaseUrl;
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String? ?? releaseUrl;
          break;
        }
      }

      final hasUpdate = isNewer(rawTag, currentVersion);

      _latestUpdate = UpdateInfo(
        latestVersion: rawTag,
        currentVersion: currentVersion,
        releaseNotes: releaseNotes,
        apkDownloadUrl: apkUrl,
        releaseUrl: releaseUrl,
        hasUpdate: hasUpdate,
      );

      _checking = false;
      notifyListeners();
      return _latestUpdate;
    } catch (e) {
      debugPrint('OTA Update check error: $e');
      _checking = false;
      notifyListeners();
      return null;
    }
  }

  /// Cleans version string of leading 'v' and spaces
  static String cleanVersion(String version) {
    return version.trim().replaceAll(RegExp(r'^[vV]'), '');
  }

  /// Compares semantic version strings (e.g. "1.1.0" > "1.0.0" or "1.1.0+2" > "1.1.0+1").
  bool isNewer(String remote, String local) {
    try {
      final sanitizedRemote = cleanVersion(remote);
      final sanitizedLocal = cleanVersion(local);

      final remoteBase = sanitizedRemote.split('+').first.split('-').first;
      final localBase = sanitizedLocal.split('+').first.split('-').first;

      final remoteParts = remoteBase.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final localParts = localBase.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (remoteParts.length < 3) {
        remoteParts.add(0);
      }
      while (localParts.length < 3) {
        localParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > localParts[i]) return true;
        if (remoteParts[i] < localParts[i]) return false;
      }

      // If base version matches, compare build numbers if present
      final remoteBuild = sanitizedRemote.contains('+') ? int.tryParse(sanitizedRemote.split('+').last) ?? 0 : 0;
      final localBuild = sanitizedLocal.contains('+') ? int.tryParse(sanitizedLocal.split('+').last) ?? 0 : 0;
      if (remoteBuild > localBuild) return true;

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Launches the download link in the device's default browser or package installer.
  Future<bool> downloadAndInstall(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Shows a premium cinematic update dialog.
  Future<void> showUpdateDialog(BuildContext context, UpdateInfo update) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: CinemahubColors.darkSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: CinemahubRadius.allXl,
          side: BorderSide(color: CinemahubColors.primary, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CinemahubColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(CinemahubRadius.sm),
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: CinemahubColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update Available',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'v${update.latestVersion} (Current: v${update.currentVersion})',
                    style: const TextStyle(
                      color: CinemahubColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What\'s New:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CinemahubColors.darkBackground,
                borderRadius: BorderRadius.circular(CinemahubRadius.sm),
              ),
              child: SingleChildScrollView(
                child: Text(
                  update.releaseNotes,
                  style: const TextStyle(
                    color: CinemahubColors.onDarkMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Later',
              style: TextStyle(color: CinemahubColors.onDarkMuted),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: CinemahubColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CinemahubRadius.sm),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              downloadAndInstall(update.apkDownloadUrl);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}
