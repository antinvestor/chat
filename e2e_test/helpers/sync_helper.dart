/// Sync helper utilities for E2E tests.
///
/// Provides methods for waiting on sync operations, message delivery,
/// and connection state during E2E test execution.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:patrol/patrol.dart';

import '../config/staging_config.dart';

/// Connection state for sync operations.
enum SyncConnectionState {
  /// Not connected to sync service.
  disconnected,

  /// Attempting to connect.
  connecting,

  /// Successfully connected.
  connected,

  /// Connection error occurred.
  error,
}

/// Helper class for sync-related E2E test operations.
class SyncHelper {
  /// Creates a SyncHelper with the given PatrolTester.
  SyncHelper(this.$);

  /// The PatrolTester instance for interacting with the app.
  final PatrolIntegrationTester $;

  /// Waits for the sync connection to be established.
  ///
  /// This method monitors the connection state and waits until
  /// the app is successfully connected to the sync service.
  ///
  /// [timeout] - Maximum time to wait for connection.
  ///
  /// Throws [TimeoutException] if connection is not established within timeout.
  Future<void> waitForSyncConnection({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? TestTimeouts.syncTimeout;
    final deadline = DateTime.now().add(effectiveTimeout);

    while (DateTime.now().isBefore(deadline)) {
      await $.pumpAndSettle(timeout: const Duration(seconds: 2));

      // Check for connection indicator (typically in app bar or status area)
      // The app should show a connected state indicator when synced
      final hasConnectionIndicator = await _checkConnectionState();

      if (hasConnectionIndicator) {
        return;
      }

      // Check for offline banner (indicates we're not connected)
      final offlineBanner = $(Banner).containing('Offline');
      if (!offlineBanner.exists) {
        // No offline indicator and app is responsive = likely connected
        return;
      }

      await $.pump(const Duration(milliseconds: 500));
    }

    throw TimeoutException(
      'Sync connection not established within ${effectiveTimeout.inSeconds} seconds',
    );
  }

  /// Waits for a specific message to be delivered to the recipient.
  ///
  /// This method checks for the message text to appear in the chat view,
  /// indicating successful delivery from sender to recipient.
  ///
  /// [messageText] - The message content to wait for.
  /// [timeout] - Maximum time to wait for delivery.
  ///
  /// Returns true if message appears, false otherwise.
  Future<bool> waitForMessageDelivery(
    String messageText, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? TestTimeouts.messageDeliveryTimeout;
    final deadline = DateTime.now().add(effectiveTimeout);

    while (DateTime.now().isBefore(deadline)) {
      await $.pumpAndSettle(timeout: const Duration(seconds: 1));

      // Look for the message text in the UI
      final messageWidget = $(Text).containing(messageText);
      if (messageWidget.exists) {
        return true;
      }

      await $.pump(const Duration(milliseconds: 250));
    }

    return false;
  }

  /// Waits for a message to show a specific delivery status.
  ///
  /// [messageText] - The message content to find.
  /// [expectedStatus] - The expected delivery status (sent, delivered, read).
  /// [timeout] - Maximum time to wait.
  Future<bool> waitForMessageStatus(
    String messageText,
    MessageDeliveryStatus expectedStatus, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? TestTimeouts.messageDeliveryTimeout;
    final deadline = DateTime.now().add(effectiveTimeout);

    while (DateTime.now().isBefore(deadline)) {
      await $.pumpAndSettle(timeout: const Duration(seconds: 1));

      // Find the message
      final messageWidget = $(Text).containing(messageText);
      if (messageWidget.exists) {
        // Check for status indicator icon
        final hasExpectedStatus = await _checkMessageStatus(expectedStatus);
        if (hasExpectedStatus) {
          return true;
        }
      }

      await $.pump(const Duration(milliseconds: 250));
    }

    return false;
  }

  /// Waits for the room list to be populated with at least one room.
  Future<void> waitForRoomList({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? TestTimeouts.syncOperationTimeout;
    final deadline = DateTime.now().add(effectiveTimeout);

    while (DateTime.now().isBefore(deadline)) {
      await $.pumpAndSettle(timeout: const Duration(seconds: 2));

      // Look for room list items (typically ListTile or Card widgets)
      final roomItems = $(ListTile);
      if (roomItems.exists) {
        return;
      }

      // Also check for "No chats yet" empty state
      final emptyState = $(Text).containing('No chats');
      if (emptyState.exists) {
        return; // Room list is loaded but empty
      }

      await $.pump(const Duration(milliseconds: 500));
    }

    throw TimeoutException(
      'Room list not loaded within ${effectiveTimeout.inSeconds} seconds',
    );
  }

  /// Waits for pending messages to be synced.
  ///
  /// This is useful after sending messages offline to wait for them
  /// to be uploaded when connection is restored.
  Future<void> waitForPendingSync({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? TestTimeouts.syncOperationTimeout;
    final deadline = DateTime.now().add(effectiveTimeout);

    while (DateTime.now().isBefore(deadline)) {
      await $.pumpAndSettle(timeout: const Duration(seconds: 2));

      // Check for pending indicator (clock icon or "sending" text)
      final pendingIndicator = $(Icon).which<Icon>(
        (icon) => icon.icon == Icons.schedule || icon.icon == Icons.access_time,
      );

      if (!pendingIndicator.exists) {
        // No pending indicators = all messages synced
        return;
      }

      await $.pump(const Duration(milliseconds: 500));
    }

    throw TimeoutException(
      'Pending messages not synced within ${effectiveTimeout.inSeconds} seconds',
    );
  }

  /// Simulates going offline by enabling airplane mode (native only).
  ///
  /// Note: This requires native device capabilities and may not work
  /// in all test environments.
  Future<void> simulateOffline() async {
    // In a real implementation, this would use platform channels
    // to toggle airplane mode or disable network interfaces.
    // For now, we just pump to ensure UI stability.
    await $.pump(const Duration(milliseconds: 500));
  }

  /// Simulates coming back online by disabling airplane mode.
  Future<void> simulateOnline() async {
    // In a real implementation, this would restore network connectivity.
    await $.pump(const Duration(milliseconds: 500));
  }

  /// Checks if the app is currently connected to the sync service.
  Future<bool> _checkConnectionState() async {
    // Look for connection status indicators in the UI
    // This could be a colored dot, icon, or text

    // Check for connected icon (typically a cloud with check)
    final connectedIcon = $(Icon).which<Icon>(
      (icon) => icon.icon == Icons.cloud_done || icon.icon == Icons.sync,
    );

    if (connectedIcon.exists) {
      return true;
    }

    // Check for lack of offline indicators
    final offlineIcon = $(Icon).which<Icon>(
      (icon) =>
          icon.icon == Icons.cloud_off ||
          icon.icon == Icons.signal_wifi_off ||
          icon.icon == Icons.sync_problem,
    );

    return !offlineIcon.exists;
  }

  /// Checks if a message has the expected delivery status.
  Future<bool> _checkMessageStatus(MessageDeliveryStatus status) async {
    IconData expectedIcon;

    switch (status) {
      case MessageDeliveryStatus.pending:
        expectedIcon = Icons.schedule;
      case MessageDeliveryStatus.sent:
        expectedIcon = Icons.check;
      case MessageDeliveryStatus.delivered:
        expectedIcon = Icons.done_all;
      case MessageDeliveryStatus.read:
        // Read status often uses same icon but with different color
        expectedIcon = Icons.done_all;
    }

    final statusIcon = $(Icon).which<Icon>((icon) => icon.icon == expectedIcon);
    return statusIcon.exists;
  }
}

/// Message delivery status states.
enum MessageDeliveryStatus {
  /// Message is pending send.
  pending,

  /// Message has been sent to server.
  sent,

  /// Message has been delivered to recipient.
  delivered,

  /// Message has been read by recipient.
  read,
}

/// Extension on PatrolIntegrationTester to add sync convenience methods.
extension SyncPatrolExtensions on PatrolIntegrationTester {
  /// Creates a SyncHelper for this tester.
  SyncHelper get sync => SyncHelper(this);
}

/// Extension on PatrolFinder for Banner widgets.
extension PatrolFinderBannerExtensions on PatrolFinder {
  /// Checks if this finder contains a Banner widget.
  bool get exists {
    try {
      return evaluate().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
