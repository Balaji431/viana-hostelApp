import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'app_logger.dart';

/// Service managing Android-native In-App Updates via Google Play Core API.
///
/// Handles:
/// 1. Checking for available updates against Google Play.
/// 2. Flexible updates (background download with non-blocking user experience).
/// 3. Immediate updates (full-screen blocking flow for critical/breaking updates).
/// 4. Safe failure handling (silently logs when sideloaded, running in debug,
///    or on non-Android platforms).
class PlayUpdateService {
  static bool _isChecking = false;
  static DateTime? _lastCheckTime;

  /// Cooldown between background checks to avoid spamming Google Play API.
  static const Duration _checkCooldown = Duration(minutes: 15);

  /// Priority threshold (0 to 5) configured in Google Play Console or API.
  /// Priority >= 4 triggers an Immediate Update; lower triggers Flexible.
  static const int _immediatePriorityThreshold = 4;

  /// Staleness threshold in days. If the user is running a build older than
  /// this many days and an update is available, escalate to Immediate Update.
  static const int _stalenessThresholdDays = 30;

  /// Check Google Play for updates and prompt the user if available.
  ///
  /// [context] is optional, used to display a SnackBar when a Flexible update
  /// has finished downloading so the user can restart when ready.
  /// [forceImmediate] forces Immediate mode regardless of priority/staleness.
  static Future<void> checkForUpdate({
    BuildContext? context,
    bool forceImmediate = false,
  }) async {
    // Google Play In-App Updates is Android-only
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    // Prevent concurrent checks
    if (_isChecking) return;

    // Cooldown check
    final now = DateTime.now();
    if (_lastCheckTime != null &&
        now.difference(_lastCheckTime!) < _checkCooldown) {
      return;
    }

    _isChecking = true;
    _lastCheckTime = now;

    try {
      AppLogger.info("Checking for Google Play in-app updates...");
      final AppUpdateInfo info = await InAppUpdate.checkForUpdate();

      // If an immediate or flexible update was already in progress
      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        }
        return;
      }

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        AppLogger.info(
          "InAppUpdate: No update available (availability=${info.updateAvailability}).",
        );
        return;
      }

      AppLogger.info(
        "InAppUpdate: Update available! "
        "AvailableVersionCode: ${info.availableVersionCode}, "
        "Priority: ${info.updatePriority}, "
        "StalenessDays: ${info.clientVersionStalenessDays}, "
        "FlexibleAllowed: ${info.flexibleUpdateAllowed}, "
        "ImmediateAllowed: ${info.immediateUpdateAllowed}",
      );

      final isCritical = forceImmediate ||
          info.updatePriority >= _immediatePriorityThreshold ||
          ((info.clientVersionStalenessDays ?? 0) >= _stalenessThresholdDays);

      if (isCritical && info.immediateUpdateAllowed) {
        // --- Immediate Update (Blocking) ---
        AppLogger.info("InAppUpdate: Initiating Immediate Update...");
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        // --- Flexible Update (Non-blocking background download) ---
        AppLogger.info("InAppUpdate: Starting Flexible Update...");
        final result = await InAppUpdate.startFlexibleUpdate();
        AppLogger.info("InAppUpdate: Flexible update download completed: $result");

        // Notify user that the update is ready to install
        if (context != null && context.mounted) {
          _showFlexibleUpdateReadySnackBar(context);
        } else {
          // If no UI context is mounted, install directly
          await InAppUpdate.completeFlexibleUpdate();
        }
      } else if (info.immediateUpdateAllowed) {
        // Fallback: If flexible is not allowed, use immediate
        AppLogger.info("InAppUpdate: Flexible not allowed, falling back to Immediate Update...");
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      // NOTE: When sideloaded, running debug builds, or if Play Store API is unavailable,
      // Google Play returns error codes like ERROR_API_NOT_AVAILABLE (-3).
      // This is expected outside official Play Store distribution.
      AppLogger.warning("InAppUpdate check failed (expected in debug/sideload): $e");
    } finally {
      _isChecking = false;
    }
  }

  /// Displays a non-intrusive banner/snack notifying the user that the
  /// flexible update has downloaded and can be applied now.
  static void _showFlexibleUpdateReadySnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.system_update_rounded, color: Colors.white, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'An update for VStay has been downloaded.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(days: 1), // Keep visible until action
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'RESTART NOW',
          textColor: const Color(0xFF38BDF8),
          onPressed: () async {
            try {
              await InAppUpdate.completeFlexibleUpdate();
            } catch (e) {
              AppLogger.error("Failed to complete flexible update: $e");
            }
          },
        ),
      ),
    );
  }
}
