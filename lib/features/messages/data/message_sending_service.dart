import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xid/xid.dart';

import '../../../core/crypto/e2e_encryption_service.dart';
import '../../../core/crypto/key_exchange_service.dart';
import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/media/media_compression_service.dart';
import '../../../core/media/thumbnail_service.dart';
import '../../../core/sync/pending_job.dart';
import '../../../core/sync/pending_job_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../features/auth/data/auth_repository.dart';
import '../domain/room_event.dart' as domain;
import 'file_upload_service.dart';
import 'message_providers.dart';
import 'message_repository.dart';

/// Service for sending messages with support for:
/// - Text messages
/// - Media messages (images, videos, audio, files)
/// - Encrypted messages (E2E)
/// - Offline queue with retry
/// - Media compression before upload
/// - Client-side thumbnail generation
class MessageSendingService {
  MessageSendingService(
    this._messageRepo,
    this._jobRepo,
    this._fileUploadService,
    this._encryptionService,
    this._compressionService,
    this._thumbnailService,
    this._getCurrentProfileId,
  );
  final MessageRepository _messageRepo;
  final PendingJobRepository _jobRepo;
  final FileUploadService _fileUploadService;
  final E2EEncryptionService _encryptionService;
  final MediaCompressionService _compressionService;
  final ThumbnailService _thumbnailService;
  final Future<String> Function() _getCurrentProfileId;

  /// Send a text message
  ///
  /// Messages are encrypted by default using Megolm (E2EE).
  /// Set [encrypt] to false to send unencrypted (not recommended).
  Future<domain.RoomEvent> sendTextMessage({
    required String roomId,
    required String text,
    String? replyToId,
    bool encrypt = true, // E2EE enabled by default
  }) async {
    final localId = Xid().toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final senderId = await _getCurrentProfileId();

    var content = <String, dynamic>{'text': text};

    // Encrypt by default for security
    if (encrypt) {
      try {
        await _encryptionService.initialize();
        final encrypted = await _encryptionService.encryptGroup(roomId, text);
        content = {
          'encrypted': true,
          'ciphertext': encrypted.ciphertext,
          'sessionId': encrypted.sessionId,
          'messageIndex': encrypted.messageIndex,
          'senderKey': encrypted.senderKey,
        };
        AppLogger.debug(
          'Message encrypted',
          data: {'roomId': roomId, 'sessionId': encrypted.sessionId},
        );
      } catch (e, stackTrace) {
        AppLogger.error(
          'Encryption failed, sending unencrypted',
          error: e,
          stackTrace: stackTrace,
        );
        // Fall back to unencrypted - add warning flag
        content['encryptionFailed'] = true;
      }
    }

    final event = domain.RoomEvent(
      id: localId,
      roomId: roomId,
      senderId: senderId,
      type: domain.RoomEventType.text,
      content: content,
      parentId: replyToId,
      createdAt: now,
      localId: localId,
    );

    // Save locally first
    await _messageRepo.insertMessage(event);

    // Queue for upload
    await _jobRepo.addJob(JobType.sendMessage, {
      'roomId': roomId,
      'type': event.type.toString(),
      'content': content,
      'localId': localId,
      'parentId': replyToId,
    });

    AppLogger.debug(
      'Text message queued',
      data: {'localId': localId, 'roomId': roomId},
    );
    return event;
  }

  /// Send an image message with optional compression
  ///
  /// Parameters:
  /// - [roomId]: The room to send the message to
  /// - [imageFile]: The image file to send
  /// - [caption]: Optional caption for the image
  /// - [replyToId]: Optional message ID to reply to
  /// - [encrypt]: Whether to encrypt the message (default: false)
  /// - [keepOriginal]: If true, skip compression and send original
  /// - [imageQuality]: JPEG quality (0-100) for compression
  /// - [onProgress]: Progress callback for compression and upload
  Future<domain.RoomEvent> sendImageMessage({
    required String roomId,
    required File imageFile,
    String? caption,
    String? replyToId,
    bool encrypt = false,
    bool keepOriginal = false,
    int? imageQuality,
    void Function(double progress)? onProgress,
    void Function(CompressionProgress progress)? onCompressionProgress,
  }) async {
    var fileToSend = imageFile;

    // Compress image if not keeping original
    if (!keepOriginal) {
      final compressionResult = await _compressionService.compressImage(
        imageFile,
        quality: imageQuality,
        onProgress: onCompressionProgress,
      );
      fileToSend = compressionResult.file;

      if (compressionResult.wasCompressed) {
        AppLogger.info(
          'Image compressed before sending',
          data: {
            'originalSize': compressionResult.originalSize,
            'compressedSize': compressionResult.compressedSize,
            'savingsPercent': compressionResult.savingsPercent.toStringAsFixed(
              1,
            ),
          },
        );
      }
    }

    return _sendMediaMessage(
      roomId: roomId,
      file: fileToSend,
      type: domain.RoomEventType.image,
      caption: caption,
      replyToId: replyToId,
      encrypt: encrypt,
      onProgress: onProgress,
    );
  }

  /// Send a video message with optional compression
  ///
  /// Parameters:
  /// - [roomId]: The room to send the message to
  /// - [videoFile]: The video file to send
  /// - [caption]: Optional caption for the video
  /// - [replyToId]: Optional message ID to reply to
  /// - [encrypt]: Whether to encrypt the message (default: false)
  /// - [keepOriginal]: If true, skip compression and send original
  /// - [videoQuality]: Quality preset for video compression
  /// - [onProgress]: Progress callback for upload
  /// - [onCompressionProgress]: Progress callback for compression
  Future<domain.RoomEvent> sendVideoMessage({
    required String roomId,
    required File videoFile,
    String? caption,
    String? replyToId,
    bool encrypt = false,
    bool keepOriginal = false,
    CompressionQualityPreset? videoQuality,
    void Function(double progress)? onProgress,
    void Function(CompressionProgress progress)? onCompressionProgress,
  }) async {
    var fileToSend = videoFile;

    // Compress video if not keeping original
    if (!keepOriginal) {
      final compressionResult = await _compressionService.compressVideo(
        videoFile,
        qualityPreset: videoQuality,
        onProgress: onCompressionProgress,
      );
      fileToSend = compressionResult.file;

      if (compressionResult.wasCompressed) {
        AppLogger.info(
          'Video compressed before sending',
          data: {
            'originalSize': compressionResult.originalSize,
            'compressedSize': compressionResult.compressedSize,
            'savingsPercent': compressionResult.savingsPercent.toStringAsFixed(
              1,
            ),
            'width': compressionResult.width,
            'height': compressionResult.height,
          },
        );
      }
    }

    return _sendMediaMessage(
      roomId: roomId,
      file: fileToSend,
      type: domain.RoomEventType.video,
      caption: caption,
      replyToId: replyToId,
      encrypt: encrypt,
      onProgress: onProgress,
    );
  }

  /// Send an audio message
  Future<domain.RoomEvent> sendAudioMessage({
    required String roomId,
    required File audioFile,
    int? durationMs,
    String? replyToId,
    bool encrypt = false,
    void Function(double progress)? onProgress,
  }) async => _sendMediaMessage(
    roomId: roomId,
    file: audioFile,
    type: domain.RoomEventType.audio,
    extraContent: durationMs != null ? {'duration': durationMs} : null,
    replyToId: replyToId,
    encrypt: encrypt,
    onProgress: onProgress,
  );

  /// Send a file message
  Future<domain.RoomEvent> sendFileMessage({
    required String roomId,
    required File file,
    String? replyToId,
    bool encrypt = false,
    void Function(double progress)? onProgress,
  }) async => _sendMediaMessage(
    roomId: roomId,
    file: file,
    type: domain.RoomEventType.file,
    replyToId: replyToId,
    encrypt: encrypt,
    onProgress: onProgress,
  );

  /// Internal method for sending media messages
  Future<domain.RoomEvent> _sendMediaMessage({
    required String roomId,
    required File file,
    required domain.RoomEventType type,
    String? caption,
    String? replyToId,
    Map<String, dynamic>? extraContent,
    bool encrypt = false,
    void Function(double progress)? onProgress,
  }) async {
    final localId = Xid().toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final senderId = await _getCurrentProfileId();
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();

    // Generate thumbnail for images and videos
    ThumbnailResult? thumbnailResult;
    if (type == domain.RoomEventType.image) {
      thumbnailResult = await _thumbnailService.generateImageThumbnail(file);
    } else if (type == domain.RoomEventType.video) {
      thumbnailResult = await _thumbnailService.generateVideoThumbnail(file);
    }

    // Create initial content with local file path and thumbnail
    var content = <String, dynamic>{
      'localPath': file.path,
      'fileName': fileName,
      'fileSize': fileSize,
      'uploading': true,
      if (caption != null) 'caption': caption,
      if (thumbnailResult != null)
        'localThumbnailPath': thumbnailResult.file.path,
      ...?extraContent,
    };

    final event = domain.RoomEvent(
      id: localId,
      roomId: roomId,
      senderId: senderId,
      type: type,
      content: content,
      parentId: replyToId,
      createdAt: now,
      localId: localId,
    );

    // Save locally first (shows as pending with local file and thumbnail)
    await _messageRepo.insertMessage(event);

    // Upload thumbnail first (if generated)
    String? uploadedThumbnailUrl;
    if (thumbnailResult != null) {
      AppLogger.debug(
        'Uploading thumbnail',
        data: {'size': thumbnailResult.size},
      );
      final thumbUploadResult = await _fileUploadService.uploadFile(
        thumbnailResult.file,
      );
      if (thumbUploadResult.isSuccess) {
        uploadedThumbnailUrl = thumbUploadResult.fileUrl;
        AppLogger.debug(
          'Thumbnail uploaded',
          data: {'url': uploadedThumbnailUrl},
        );
      }
    }

    // Upload main file
    AppLogger.info(
      'Uploading media file',
      data: {'fileName': fileName, 'size': fileSize},
    );

    final uploadResult = await _fileUploadService.uploadFile(
      file,
      onProgress: onProgress,
    );

    if (uploadResult.isSuccess) {
      // Prefer client-uploaded thumbnail, fall back to server-generated
      final finalThumbnailUrl =
          uploadedThumbnailUrl ?? uploadResult.thumbnailUrl;

      // Update content with server URL
      content = {
        'url': uploadResult.fileUrl,
        'fileId': uploadResult.fileId,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': uploadResult.mimeType,
        if (finalThumbnailUrl != null) 'thumbnailUrl': finalThumbnailUrl,
        if (caption != null) 'caption': caption,
        ...?extraContent,
      };

      // Encrypt if requested
      if (encrypt) {
        try {
          final encrypted = await _encryptionService.encryptGroup(
            roomId,
            content.toString(),
          );
          content = {
            'encrypted': true,
            'ciphertext': encrypted.ciphertext,
            'sessionId': encrypted.sessionId,
            'originalType': type.toString(),
          };
        } catch (e) {
          AppLogger.warning(
            'Media encryption failed',
            data: {'error': e.toString()},
          );
        }
      }

      // Update local message with upload result
      final updatedEvent = event.copyWith(content: content);
      await _messageRepo.insertMessage(updatedEvent);

      // Queue for sending to chat server
      await _jobRepo.addJob(JobType.sendMediaMessage, {
        'roomId': roomId,
        'type': type.toString(),
        'content': content,
        'localId': localId,
        'parentId': replyToId,
      });

      AppLogger.info(
        'Media message queued',
        data: {'localId': localId, 'fileUrl': uploadResult.fileUrl},
      );
      return updatedEvent;
    } else {
      // Mark as failed
      final failedEvent = event.copyWith(
        status: domain.EventStatus.failed,
        content: {...content, 'error': uploadResult.errorMessage},
      );
      await _messageRepo.insertMessage(failedEvent);

      AppLogger.error(
        'Media upload failed',
        data: {'error': uploadResult.errorMessage},
      );
      return failedEvent;
    }
  }

  /// Send a reaction to a message
  Future<domain.RoomEvent> sendReaction({
    required String roomId,
    required String targetEventId,
    required String emoji,
  }) async {
    final localId = Xid().toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final senderId = await _getCurrentProfileId();

    final event = domain.RoomEvent(
      id: localId,
      roomId: roomId,
      senderId: senderId,
      type: domain.RoomEventType.reaction,
      content: {'emoji': emoji},
      parentId: targetEventId,
      createdAt: now,
      localId: localId,
    );

    await _messageRepo.insertMessage(event);

    await _jobRepo.addJob(JobType.sendMessage, {
      'roomId': roomId,
      'type': event.type.toString(),
      'content': event.content,
      'localId': localId,
      'parentId': targetEventId,
    });

    return event;
  }

  /// Send a room key event to share E2EE session keys with a recipient
  ///
  /// This is used to share Megolm session keys so other users can decrypt
  /// messages in an encrypted room. The session key is sent as a special
  /// roomKey event that recipients process to add inbound sessions.
  Future<domain.RoomEvent> sendRoomKeyEvent({
    required RoomKeyPayload payload,
  }) async {
    final localId = Xid().toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final senderId = await _getCurrentProfileId();

    // Create the content with type marker for recipient detection
    final content = {'type': 'roomKey', ...payload.toJson()};

    final event = domain.RoomEvent(
      id: localId,
      roomId: payload.roomId,
      senderId: senderId,
      type: domain.RoomEventType.roomKey,
      content: content,
      createdAt: now,
      localId: localId,
    );

    // Don't store roomKey events as regular messages - they're control messages
    // Just queue for sending
    await _jobRepo.addJob(JobType.sendMessage, {
      'roomId': payload.roomId,
      'type': event.type.toString(),
      'content': {'text': jsonEncode(content)}, // Encode as JSON text for wire
      'localId': localId,
    });

    AppLogger.debug(
      'Room key event queued',
      data: {
        'localId': localId,
        'roomId': payload.roomId,
        'recipientProfileId': payload.recipientProfileId,
        'sessionId': payload.sessionId,
      },
    );

    return event;
  }

  /// Share session keys with all specified room members
  ///
  /// Creates and sends roomKey events for each member so they can decrypt
  /// messages encrypted with our Megolm session.
  Future<void> shareSessionKeysWithMembers({
    required List<RoomKeyPayload> payloads,
  }) async {
    for (final payload in payloads) {
      try {
        await sendRoomKeyEvent(payload: payload);
      } catch (e, stackTrace) {
        AppLogger.error(
          'Failed to send room key to member',
          error: e,
          stackTrace: stackTrace,
          data: {'recipientProfileId': payload.recipientProfileId},
        );
      }
    }

    AppLogger.info(
      'Session keys shared with members',
      data: {'memberCount': payloads.length},
    );
  }

  /// Retry a failed message
  Future<void> retryMessage(String localId) async {
    final db = AppDatabase.instance;
    final query = db.select(db.roomEvents)
      ..where((t) => t.localId.equals(localId) | t.id.equals(localId));
    final results = await query.get();

    if (results.isEmpty) {
      AppLogger.warning(
        'Message not found for retry',
        data: {'localId': localId},
      );
      return;
    }

    final row = results.first;
    final type = domain.RoomEventType.values[row.type];

    // Re-queue the job
    final jobType = _isMediaType(type)
        ? JobType.sendMediaMessage
        : JobType.sendMessage;

    await _jobRepo.addJob(jobType, {
      'roomId': row.roomId,
      'type': type.toString(),
      'content': row.content ?? '',
      'localId': localId,
      'parentId': row.parentId,
    });

    // Update status to pending
    await _messageRepo.updateMessageStatus(localId, domain.EventStatus.pending);

    AppLogger.info('Message retry queued', data: {'localId': localId});
  }

  /// Delete a local message (before it's sent)
  Future<void> deleteLocalMessage(String localId) async {
    final db = AppDatabase.instance;
    await (db.delete(db.roomEvents)..where(
          (t) =>
              t.localId.equals(localId) &
              t.status.equals(domain.EventStatus.pending.index),
        ))
        .go();
  }

  /// Edit an existing text message
  ///
  /// Returns true if the edit was successfully queued, false if editing
  /// is not allowed (not own message, outside time window, not text type).
  Future<bool> editTextMessage({
    required String messageId,
    required String newText,
    Duration editWindow = const Duration(minutes: 15),
  }) async {
    final currentUserId = await _getCurrentProfileId();

    // Check if message can be edited
    final canEdit = await _messageRepo.canEditMessage(
      messageId,
      currentUserId,
      editWindow: editWindow,
    );

    if (!canEdit) {
      AppLogger.warning(
        'Cannot edit message',
        data: {'messageId': messageId, 'userId': currentUserId},
      );
      return false;
    }

    // Get the original message
    final originalEvent = await _messageRepo.getEventById(messageId);
    if (originalEvent == null) return false;

    // Preserve original content if first edit
    final originalContent = originalEvent.isEdited
        ? null // Don't overwrite if already edited before
        : originalEvent.content['text'] as String?;

    final newContent = {'text': newText};

    // Update locally first (optimistic update)
    await _messageRepo.updateMessageContent(
      messageId,
      newContent,
      originalContent: originalContent,
    );

    // Queue for sync to server
    await _jobRepo.addJob(JobType.editMessage, {
      'messageId': messageId,
      'roomId': originalEvent.roomId,
      'content': newContent,
      'originalContent': originalContent,
    });

    AppLogger.info('Message edit queued', data: {'messageId': messageId});
    return true;
  }

  /// Check if a message can be edited (async - fetches from DB)
  Future<bool> canEdit(String messageId) async {
    final currentUserId = await _getCurrentProfileId();
    return _messageRepo.canEditMessage(messageId, currentUserId);
  }

  /// Check if a message can be edited (sync - for UI when message data is available)
  ///
  /// Use this method when you already have the message data to avoid
  /// unnecessary database lookups. This is the single source of truth
  /// for edit validation logic.
  static bool canEditMessage({
    required bool isOwnMessage,
    required domain.RoomEventType messageType,
    required domain.EventStatus messageStatus,
    required int messageCreatedAt,
    Duration editWindow = const Duration(minutes: 15),
  }) {
    // Must be own message
    if (!isOwnMessage) return false;

    // Must be text type
    if (messageType != domain.RoomEventType.text) return false;

    // Must not be pending or failed
    if (messageStatus == domain.EventStatus.pending ||
        messageStatus == domain.EventStatus.failed) {
      return false;
    }

    // Must be within edit window
    final messageAge = DateTime.now().millisecondsSinceEpoch - messageCreatedAt;
    if (messageAge > editWindow.inMilliseconds) return false;

    return true;
  }

  /// Delete a message for everyone
  ///
  /// Returns true if the deletion was successfully queued, false if deleting
  /// is not allowed (not own message, outside time window, already deleted).
  Future<bool> deleteMessage({
    required String messageId,
    Duration deleteWindow = const Duration(hours: 24),
  }) async {
    final currentUserId = await _getCurrentProfileId();

    // Check if message can be deleted
    final canDelete = await _messageRepo.canDeleteMessage(
      messageId,
      currentUserId,
      deleteWindow: deleteWindow,
    );

    if (!canDelete) {
      AppLogger.warning(
        'Cannot delete message',
        data: {'messageId': messageId, 'userId': currentUserId},
      );
      return false;
    }

    // Get the original message for roomId
    final originalEvent = await _messageRepo.getEventById(messageId);
    if (originalEvent == null) return false;

    // Mark as deleted locally first (optimistic update)
    await _messageRepo.deleteMessage(messageId, deletedBy: currentUserId);

    // Queue for sync to server
    await _jobRepo.addJob(JobType.deleteMessage, {
      'messageId': messageId,
      'roomId': originalEvent.roomId,
    });

    AppLogger.info('Message delete queued', data: {'messageId': messageId});
    return true;
  }

  /// Delete a message for the current user only (local deletion)
  ///
  /// This removes the message from the local database only.
  /// Other users will still see the message.
  Future<void> deleteMessageForMe(String messageId) async {
    await _messageRepo.deleteMessageForMe(messageId);
    AppLogger.info('Message deleted locally', data: {'messageId': messageId});
  }

  /// Check if a message can be deleted (async - fetches from DB)
  Future<bool> canDelete(String messageId, {bool isAdmin = false}) async {
    final currentUserId = await _getCurrentProfileId();
    return _messageRepo.canDeleteMessage(
      messageId,
      currentUserId,
      isAdmin: isAdmin,
    );
  }

  /// Check if a message can be deleted (sync - for UI when message data is available)
  ///
  /// Use this method when you already have the message data to avoid
  /// unnecessary database lookups. This is the single source of truth
  /// for delete validation logic.
  static bool canDeleteMessage({
    required bool isOwnMessage,
    required domain.EventStatus messageStatus,
    required int messageCreatedAt,
    required bool isDeleted,
    bool isAdmin = false,
    Duration deleteWindow = const Duration(hours: 24),
  }) {
    // Already deleted
    if (isDeleted) return false;

    // Admins can delete any message
    if (isAdmin) return true;

    // Must be own message
    if (!isOwnMessage) return false;

    // Must not be pending or failed (use cancel instead)
    if (messageStatus == domain.EventStatus.pending ||
        messageStatus == domain.EventStatus.failed) {
      return false;
    }

    // Must be within delete window
    final messageAge = DateTime.now().millisecondsSinceEpoch - messageCreatedAt;
    if (messageAge > deleteWindow.inMilliseconds) return false;

    return true;
  }

  bool _isMediaType(domain.RoomEventType type) =>
      type == domain.RoomEventType.image ||
      type == domain.RoomEventType.video ||
      type == domain.RoomEventType.audio ||
      type == domain.RoomEventType.file;
}

// Provider
final messageSendingServiceProvider = Provider<MessageSendingService>((ref) {
  final messageRepo = ref.watch(messageRepositoryProvider);
  final jobRepo = ref.watch(pendingJobRepositoryProvider);
  final fileUploadService = ref.watch(fileUploadServiceProvider);
  final encryptionService = ref.watch(e2eEncryptionServiceProvider);
  final compressionService = ref.watch(mediaCompressionServiceProvider);
  final thumbnailService = ref.watch(thumbnailServiceProvider);
  final authRepo = ref.watch(authRepositoryProvider);

  return MessageSendingService(
    messageRepo,
    jobRepo,
    fileUploadService,
    encryptionService,
    compressionService,
    thumbnailService,
    () async {
      final profileId = await authRepo.getCurrentProfileId();
      return profileId ?? 'unknown_user';
    },
  );
});
