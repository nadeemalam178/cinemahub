import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/cinemahub_colors.dart';

/// Information regarding an available OTA update.
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String apkDownloadUrl;
  final String releaseUrl;
  final bool hasUpdate;
  final int? apkSizeBytes;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.releaseUrl,
    required this.hasUpdate,
    this.apkSizeBytes,
  });
}

/// Service handling Over-The-Air (OTA) updates by querying GitHub Releases,
/// downloading APKs in-app with live progress, and invoking the native Android package installer.
class UpdateService extends ChangeNotifier {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const MethodChannel _installerChannel = MethodChannel('com.cinemahub.app/installer');

  bool _checking = false;
  bool get checking => _checking;

  UpdateInfo? _latestUpdate;
  UpdateInfo? get latestUpdate => _latestUpdate;

  // Live in-app download state
  bool _downloading = false;
  bool get downloading => _downloading;
  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;
  String? _downloadedApkPath;
  String? get downloadedApkPath => _downloadedApkPath;

  /// Check GitHub releases for an update.
  Future<UpdateInfo?> checkForUpdate({String repo = 'nadeemalam178/cinemahub'}) async {
    _checking = true;
    notifyListeners();

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = packageInfo.buildNumber;
      final localFull = currentBuild.isNotEmpty ? '$currentVersion+$currentBuild' : currentVersion;

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
      final rawTag = cleanVersion((data['tag_name'] as String? ?? ''));
      final releaseNotes = data['body'] as String? ?? 'A new version of CinemaHub is available with performance and streaming upgrades.';
      final releaseUrl = data['html_url'] as String? ?? 'https://github.com/$repo/releases';

      // Find the direct APK asset URL
      String apkUrl = releaseUrl;
      int? apkSize;
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String? ?? releaseUrl;
          apkSize = (asset['size'] as num?)?.toInt();
          break;
        }
      }

      final hasUpdate = isNewer(rawTag, localFull);

      _latestUpdate = UpdateInfo(
        latestVersion: rawTag,
        currentVersion: currentVersion,
        releaseNotes: releaseNotes,
        apkDownloadUrl: apkUrl,
        releaseUrl: releaseUrl,
        hasUpdate: hasUpdate,
        apkSizeBytes: apkSize,
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

  /// Cleans version string of leading 'v' or 'V' and spaces
  static String cleanVersion(String version) {
    return version.trim().replaceAll(RegExp(r'^[vV]'), '');
  }

  /// Compares semantic version strings (e.g. "1.4.1" > "1.4.0" or "1.4.0+6" > "1.4.0+5").
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

      // Base versions match: check build numbers if available
      final remoteHasBuild = sanitizedRemote.contains('+');
      final localHasBuild = sanitizedLocal.contains('+');

      if (remoteHasBuild && localHasBuild) {
        final remoteBuild = int.tryParse(sanitizedRemote.split('+').last) ?? 0;
        final localBuild = int.tryParse(sanitizedLocal.split('+').last) ?? 0;
        return remoteBuild > localBuild;
      }

      // If remote does not have a higher build number and bases are identical, it is NOT newer
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the APK directly into local cache with progress callback and triggers native installation.
  Future<void> downloadAndInstallApk({
    required String url,
    required void Function(double progress, int received, int total) onProgress,
    required void Function(String error) onError,
    required void Function(String path) onCompleted,
  }) async {
    _downloading = true;
    _downloadProgress = 0.0;
    notifyListeners();

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/cinemahub-update.apk';
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            _downloadProgress = progress;
            onProgress(progress, received, total);
            notifyListeners();
          }
        },
      );

      _downloading = false;
      _downloadProgress = 1.0;
      _downloadedApkPath = savePath;
      notifyListeners();

      onCompleted(savePath);

      // Trigger native Android installation
      await installApk(savePath);
    } catch (e) {
      _downloading = false;
      notifyListeners();
      debugPrint('In-app APK download error: $e');
      onError(e.toString());
      // Fallback: open in external browser
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Invokes the native Kotlin installer channel to prompt Android PackageInstaller
  Future<bool> installApk(String filePath) async {
    try {
      final result = await _installerChannel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return result ?? false;
    } catch (e) {
      debugPrint('Native install channel error: $e');
      return false;
    }
  }

  /// Shows a modern glassmorphic, structured update dialog with in-app download & install.
  Future<void> showUpdateDialog(BuildContext context, UpdateInfo update) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ModernOtaUpdateDialog(
        update: update,
        updateService: this,
      ),
    );
  }
}

class _ModernOtaUpdateDialog extends StatefulWidget {
  const _ModernOtaUpdateDialog({
    required this.update,
    required this.updateService,
  });

  final UpdateInfo update;
  final UpdateService updateService;

  @override
  State<_ModernOtaUpdateDialog> createState() => _ModernOtaUpdateDialogState();
}

class _ModernOtaUpdateDialogState extends State<_ModernOtaUpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String _statusText = 'Ready to download';
  String? _downloadedPath;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.updateService.downloadedApkPath != null) {
      _downloadedPath = widget.updateService.downloadedApkPath;
      _statusText = 'Downloaded & ready to install';
    }
  }

  void _startDownload() {
    setState(() {
      _downloading = true;
      _errorMessage = null;
      _statusText = 'Downloading update...';
    });

    widget.updateService.downloadAndInstallApk(
      url: widget.update.apkDownloadUrl,
      onProgress: (prog, received, total) {
        if (!mounted) return;
        final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
        final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
        final pct = (prog * 100).toInt();
        setState(() {
          _progress = prog;
          _statusText = '$recMb MB / $totMb MB ($pct%)';
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _errorMessage = 'Download failed. Opening in browser...';
          _statusText = 'Failed';
        });
      },
      onCompleted: (path) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _downloadedPath = path;
          _progress = 1.0;
          _statusText = 'Download complete! Tap Install.';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sizeMb = widget.update.apkSizeBytes != null
        ? '${(widget.update.apkSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : 'APK Release';

    final cleanNotes = _formatChangelog(widget.update.releaseNotes);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF14141E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: CinemahubColors.primary.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: CinemahubColors.primary.withValues(alpha: 0.25),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [CinemahubColors.primary, Color(0xFF990000)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: CinemahubColors.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Update Available',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: CinemahubColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: CinemahubColors.gold.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'v${widget.update.latestVersion}',
                              style: const TextStyle(
                                color: CinemahubColors.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Current: v${widget.update.currentVersion}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          const Spacer(),
                          Text(
                            sizeMb,
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Changelog Title
            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: CinemahubColors.gold, size: 16),
                SizedBox(width: 6),
                Text(
                  'What\'s New in This Version',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Clean Formatted Changelog Container
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  cleanNotes,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],

            const SizedBox(height: 18),

            // Download Progress Bar (When downloading or complete)
            if (_downloading || _downloadedPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(CinemahubColors.primary),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _statusText,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
            ],

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later', style: TextStyle(color: Colors.white60)),
                ),
                const SizedBox(width: 8),
                if (_downloadedPath != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    onPressed: () {
                      widget.updateService.installApk(_downloadedPath!);
                    },
                    icon: const Icon(Icons.install_mobile_rounded, size: 18),
                    label: const Text('Install Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: CinemahubColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    onPressed: _downloading ? null : _startDownload,
                    icon: _downloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      _downloading ? 'Downloading...' : 'Download & Install',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatChangelog(String raw) {
    if (raw.trim().isEmpty) {
      return '• Performance improvements and bug fixes.\n• Enhanced streaming stability and zero-ad playback.';
    }
    // Clean up GitHub markdown hashes and bullet points for display
    final lines = raw.split('\n');
    final formatted = <String>[];
    for (final line in lines) {
      var l = line.trim();
      if (l.startsWith('#')) {
        l = l.replaceAll(RegExp(r'^#+\s*'), '✨ ');
      } else if (l.startsWith('* ') || l.startsWith('- ')) {
        l = '• ${l.substring(2)}';
      }
      if (l.isNotEmpty && !l.startsWith('Full Changelog')) {
        formatted.add(l);
      }
    }
    return formatted.isEmpty ? raw : formatted.join('\n');
  }
}
