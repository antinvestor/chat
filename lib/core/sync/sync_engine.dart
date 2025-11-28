import 'dart:async';
import 'dart:convert';
import 'package:connectrpc/connect.dart' as connect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../apis/chat/v1/chat.connect.client.dart';
import '../../apis/chat/v1/chat.pb.dart' as pb;
import '../../features/messages/data/message_providers.dart';
import '../../features/messages/data/message_repository.dart';
import '../../features/messages/domain/room_event.dart';
import '../crypto/key_manager.dart';
import '../db/database.dart';
import '../networking/client.dart';

import 'pending_job.dart';
import 'pending_job_repository.dart';

final pendingJobRepositoryProvider = Provider<PendingJobRepository>((ref) {
  return PendingJobRepository(AppDatabase.instance);
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    ref.watch(gatewayServiceClientProvider),
    ref.watch(chatServiceClientProvider),
    ref.watch(messageRepositoryProvider),
    ref.watch(pendingJobRepositoryProvider),
    KeyManager(AppDatabase.instance.storage),
  );
});

class SyncEngine {
  final GatewayServiceClient _gatewayClient;
  final ChatServiceClient _chatClient;
  final MessageRepository _messageRepo;
  final PendingJobRepository _jobRepo;
  final KeyManager _keyManager;

  StreamSubscription? _connectSubscription;
  Timer? _uploadTimer;
  bool _isUploading = false;

  SyncEngine(
    this._gatewayClient,
    this._chatClient,
    this._messageRepo,
    this._jobRepo,
    this._keyManager,
  );

  void start() {
    _startDownloadLoop();
    _startUploadLoop();
  }

  void stop() {
    _connectSubscription?.cancel();
    _uploadTimer?.cancel();
  }

  Future<void> _startDownloadLoop() async {
    // TODO: Handle reconnection and backoff
    final stream = _gatewayClient.connect(Stream.value(pb.ConnectRequest()));
    
    _connectSubscription = stream.listen((response) async {
      if (response.hasMessage()) {
        await _processRoomEvent(response.message);
      }
    }, onError: (e) {
      print('Sync error: $e');
    });
  }

  Future<void> _processRoomEvent(pb.RoomEvent event) async {
    // Decrypt if needed
    Map<String, dynamic> content = {};
    // ... (decryption logic)

    final roomEvent = RoomEvent(
      id: event.id,
      roomId: event.roomId,
      senderId: event.senderId,
      type: _mapEventType(event.type),
      content: content,
      parentId: event.hasParentId() ? event.parentId : null,
      status: EventStatus.delivered,
      createdAt: event.sentAt.seconds.toInt() * 1000,
      serverTs: event.sentAt.seconds.toInt() * 1000,
    );

    await _messageRepo.insertMessage(roomEvent);
  }

  void _startUploadLoop() {
    _uploadTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isUploading) return;
      _isUploading = true;
      
      try {
        final jobs = await _jobRepo.getPendingJobs();
        for (final job in jobs) {
          await _processJob(job);
        }
      } finally {
        _isUploading = false;
      }
    });
  }

  Future<void> _processJob(PendingJob job) async {
    try {
      switch (job.type) {
        case JobType.sendMessage:
          await _processSendMessage(job);
          break;
        default:
          break;
      }
      await _jobRepo.deleteJob(job.id);
    } catch (e) {
      print('Job failed: $e');
      await _jobRepo.incrementRetry(job.id);
    }
  }

  Future<void> _processSendMessage(PendingJob job) async {
    final payload = job.payload;
    final event = pb.RoomEvent(
      roomId: payload['roomId'],
      type: pb.RoomEventType.ROOM_EVENT_TYPE_TEXT, // TODO: Map correctly
      // payload: ...
    );
    
    final request = pb.SendEventRequest(event: [event]);
    await _chatClient.sendEvent(request);
    
    // Update local message status
    if (payload['localId'] != null) {
      // await _messageRepo.updateMessageStatus(payload['localId'], EventStatus.sent);
    }
  }

  RoomEventType _mapEventType(pb.RoomEventType type) {
    switch (type) {
      case pb.RoomEventType.ROOM_EVENT_TYPE_TEXT:
        return RoomEventType.text;
      default:
        return RoomEventType.text;
    }
  }
}

extension on AppDatabase {
  // Temporary helper until KeyManager uses provider properly
  get storage => const FlutterSecureStorage(); 
}
