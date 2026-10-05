import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import 'app_logger.dart';
import 'play_update_service.dart';

/// Centralized configuration for the local app version.
class AppVersionConfig {
  static const int appVersionCode = 27;
  static const String appVersion = '1.0.2';
}

/// Unified App Update Service that coordinates between Google Play In-App Updates
/// and backend version management (mandatory / force-update control).
class AppUpdateService {
  static bool _isDialogShowing = false;
  static DateTime? _lastCheckTime;
  static const Duration _checkCooldown = Duration(minutes: 15);

  /// Checks whether an update is available or required and prompts the user.
  static Future<void> checkUpdateAndPrompt(
    BuildContext context, {
    bool forceCheck = false,
  }) async {
    // In-app store updates are not applicable on Web
    if (kIsWeb) return;

    final now = DateTime.now();
    if (!forceCheck && _lastCheckTime != null && now.difference(_lastCheckTime!) < _checkCooldown) {
      return;
    }
    _lastCheckTime = now;

    // 1. On Android, first attempt native Google Play In-App Update API
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await PlayUpdateService.checkForUpdate(context: context);
      } catch (e) {
        AppLogger.warning("PlayUpdateService check error: $e");
      }
    }

    // 2. Query backend version control endpoint for mandatory / force update checks
    try {
      final String platform = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ? 'ios' : 'android';
      final res = await ApiService.checkAppVersion(
        platform: platform,
        versionCode: AppVersionConfig.appVersionCode,
        versionName: AppVersionConfig.appVersion,
      );

      if (res['success'] == true && res['update_available'] == true) {
        final bool isForce = res['force_update'] == true;
        final String title = res['title'] ?? (isForce ? 'Update Required' : 'New Update Available');
        final String message = res['message'] ??
            (isForce
                ? 'A critical update of VStay is required to continue. Please update now.'
                : 'A newer version of VStay is available on the Play Store.');
        final String playStoreUrl = res['play_store_url'] ??
            'https://play.google.com/store/apps/details?id=com.vianasoft.stay';
        final List<dynamic> notes = (res['release_notes'] is List) ? res['release_notes'] : [];

        if (context.mounted && !_isDialogShowing) {
          _showUpdateDialog(
            context,
            isForce: isForce,
            title: title,
            message: message,
            url: playStoreUrl,
            releaseNotes: notes.map((e) => e.toString()).toList(),
          );
        }
      }
    } catch (e) {
      AppLogger.error("Failed to check app version from backend: $e");
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required bool isForce,
    required String title,
    required String message,
    required String url,
    required List<String> releaseNotes,
  }) {
    _isDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (ctx) {
        return PopScope(
          canPop: !isForce,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(
                  isForce ? Icons.system_update_alt_rounded : Icons.info_outline_rounded,
                  color: isForce ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF334155), height: 1.4),
                ),
                if (releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    "What's New:",
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 6),
                  ...releaseNotes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              note,
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!isForce)
                TextButton(
                  onPressed: () {
                    _isDialogShowing = false;
                    Navigator.pop(ctx);
                  },
                  child: Text('Later', style: GoogleFonts.inter(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                ),
              ElevatedButton(
                onPressed: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                child: Text(
                  'Update Now',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _isDialogShowing = false;
    });
  }
}
