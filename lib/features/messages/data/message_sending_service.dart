import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xid/xid.dart';

import '../../../core/crypto/e2e_encryption_service.dart';
import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
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
class MessageSendingService {
  final MessageRepository _messageRepo;
  final PendingJobRepository _jobRepo;
  final FileUploadService _fileUploadService;
  final E2EEncryptionService _encryptionService;
  final Future<String> Function() _getCurrentUserId;

  MessageSendingService(
    this._messageRepo,
    this._jobRepo,
    this._fileUploadService,
    this._encryptionService,
    this._getCurrentUserId,
  );

  /// Send a text message
  Future<domain.RoomEvent> sendTextMessage({
    required String roomId,
    required String text,
    String? replyToId,
    bool encrypt = false, // Encryption disabled by default for MVP
  }) async {
    final localId = Xid().toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final senderId = await _getCurrentUserId();

    Map<String, dynamic> content = {'text': text};

    // Encrypt if requested
    if (encrypt) {
      try {
        final encrypted = await _encryptionService.encryptGroup(roomId, text);
        content = {
          'encrypted': true,
          'ciphertext': encrypted.ciphertext,
          'sessionId': encrypted.sessionId,
          'messageIndex': encrypted.messageIndex,
        };
      } catch (e) {
        AppLogger.warning('Encryption failed, sending unencrypted', data: {'error': e.toString()});
      }
    }

    final event = domain.RoomEvent(
      id: localId,
      roomId: roomId,
      senderId: senderId,
      type: domain.RoomEventType.text,
      content: content,
      parentId: replyToId,
      status: domain.EventStatus.pending,
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

    AppLogger.debug('Text message queued', data: {'localId': localId, 'roomId': roomId});
    return event;
  }

  /// Send an image message
  Future<domain.RoomEvent> sendImageMessage({
    required String roomId,
    required File imageFile,
    String? caption,
    String? replyToId,
    bool encrypt = false,
    void Function(double progress)? onProgress,
  }) async {
    return _sendMediaMessage(
      roomId: roomId,
      file: imageFile,
      type: domain.RoomEventType.image,
      caption: caption,
      replyToId: replyToId,
      encrypt: encrypt,
      onProgress: onProgress,
    );
  }

  /// Send a video message
  Future<domain.RoomEvent> sendVideoMessage({
    required String roomId,
    required File videoFile,
    String? caption,
    String? replyToId,
    bool encrypt = false,
    void Function(double progress)? onProgress,
  }) async {
    return _sendMediaMessage(
      roomId: roomId,
      file: videoFile,
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
  }) async {
    return _sendMediaMessage(
      roomId: roomId,
      file: audioFile,
      type: domain.RoomEventType.audio,
      extraContent: durationMs != null ? {'duration': durationMs} : null,
      replyToId: replyToId,
      encrypt: encrypt,
      onProgress: onProgress,
    );
  }

  /// Send a file message
  Future<domain.RoomEvent> sendFileMessage({
    required String roomId,
    required File file,
    String? replyToId,
    bool encrypt = false,
    void Function(double progress)? onProgress,
  }) async {
    return _sendMediaMessage(
      roomId: roomId,
      file: file,
      type: domain.RoomEventType.file,
      replyToId: replyToId,
      encrypt: encrypt,
      onProgress: onProgress,
    );
  }

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
    final senderId = await _getCurrentUserId();
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();

    // Create initial content with local file path
    Map<String, dynamic> content = {
      'localPath': file.path,
      'fileName': fileName,
      'fileSize': fileSize,
      'uploading': true,
      if (caption != null) 'caption': caption,
      ...?extraContent,
    };

    final event = domain.RoomEvent(
      id: localId,
      roomId: roomId,
      senderId: senderId,
      type: type,
      content: content,
      parentId: replyToId,
      status: domain.EventStatus.pending,
      createdAt: now,
      localId: localId,
    );

    // Save locally first (shows as pending with local file)
    await _messageRepo.insertMessage(event);

    // Upload file
    AppLogger.info('Uploading media file', data: {'fileName': fileName, 'size': fileSize});

    final uploadResult = await _fileUploadService.uploadFile(
      file,
      onProgress: onProgress,
    );

    if (uploadResult.isSuccess) {
      // Update content with server URL
      content = {
        'url': uploadResult.fileUrl,
        'fileId': uploadResult.fileId,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': uploadResult.mimeType,
        if (uploadResult.thumbnailUrl != null) 'thumbnailUrl': uploadResult.thumbnailUrl,
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
          AppLogger.warning('Media encryption failed', data: {'error': e.toString()});
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

      AppLogger.info('Media message queued', data: {'localId': localId, 'fileUrl': uploadResult.fileUrl});
      return updatedEvent;
    } else {
      // Mark as failed
      final failedEvent = event.copyWith(
        status: domain.EventStatus.failed,
        content: {...content, 'error': uploadResult.errorMessage},
      );
      await _messageRepo.insertMessage(failedEvent);

      AppLogger.error('Media upload failed', data: {'error': uploadResult.errorMessage});
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
    final senderId = await _getCurrentUserId();

    final event = domain.RoomEvent(
      id: localId,
      roomId: roomId,
      senderId: senderId,
      type: domain.RoomEventType.reaction,
      content: {'emoji': emoji},
      parentId: targetEventId,
      status: domain.EventStatus.pending,
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

  /// Retry a failed message
  Future<void> retryMessage(String localId) async {
    final db = AppDatabase.instance;
    final query = db.select(db.roomEvents)
      ..where((t) => t.localId.equals(localId) | t.id.equals(localId));
    final results = await query.get();

    if (results.isEmpty) {
      AppLogger.warning('Message not found for retry', data: {'localId': localId});
      return;
    }

    final row = results.first;
    final type = domain.RoomEventType.values[row.type];

    // Re-queue the job
    final jobType = _isMediaType(type) ? JobType.sendMediaMessage : JobType.sendMessage;

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
    await (db.delete(db.roomEvents)
      ..where((t) => t.localId.equals(localId) & t.status.equals(domain.EventStatus.pending.index)))
      .go();
  }

  bool _isMediaType(domain.RoomEventType type) {
    return type == domain.RoomEventType.image ||
        type == domain.RoomEventType.video ||
        type == domain.RoomEventType.audio ||
        type == domain.RoomEventType.file;
  }
}

// Provider
final messageSendingServiceProvider = Provider<MessageSendingService>((ref) {
  final messageRepo = ref.watch(messageRepositoryProvider);
  final jobRepo = ref.watch(pendingJobRepositoryProvider);
  final fileUploadService = ref.watch(fileUploadServiceProvider);
  final encryptionService = ref.watch(e2eEncryptionServiceProvider);
  final authRepo = ref.watch(authRepositoryProvider);

  return MessageSendingService(
    messageRepo,
    jobRepo,
    fileUploadService,
    encryptionService,
    () async {
      final userId = await authRepo.getCurrentUserId();
      return userId ?? 'unknown_user';
    },
  );
});
