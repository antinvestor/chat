import 'dart:io' as io;
import 'package:connectrpc/connect.dart' as connect;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectrpc/protocol/connect.dart' as connect_protocol;
import 'package:connectrpc/protobuf.dart' as connect_protobuf;
import 'package:connectrpc/io.dart' as connect_io;
import '../db/database.dart';
import '../logging/app_logger.dart';
import '../networking/api_config.dart';
import '../../apis/chat/v1/chat.connect.client.dart';
import 'pending_job_repository.dart';
import 'pending_job.dart';
import '../../features/messages/data/message_repository.dart';
import '../../features/messages/domain/room_event.dart';
import '../../apis/chat/v1/chat.pb.dart' as pb;
import '../../apis/google/protobuf/struct.pb.dart' as google_struct;
import '../../apis/google/protobuf/timestamp.pb.dart' as google_timestamp;
import 'package:fixnum/fixnum.dart' as fixnum;

class BackgroundSyncTask {
  /// Main entry point for background sync
  /// Returns true if sync completed successfully, false otherwise
  static Future<bool> run() async {
    try {
      AppLogger.info('Starting background sync task');

      // Initialize database
      final database = AppDatabase.instance;
      final jobRepo = PendingJobRepository(database);
      final messageRepo = MessageRepository(database);

      // Get auth token
      const storage = FlutterSecureStorage();
      final accessToken = await storage.read(key: 'access_token');

      if (accessToken == null) {
        AppLogger.debug('No access token found, skipping background sync');
        return true; // Not a failure, just nothing to do
      }

      // Create auth headers
      final authHeaders = connect.Headers();
      authHeaders['Authorization'] = 'Bearer $accessToken';

      // Initialize API client with optimized HTTP client
      final httpClient = io.HttpClient();
      httpClient.connectionTimeout = ApiConfig.connectionTimeout;
      httpClient.idleTimeout = ApiConfig.idleTimeout;
      httpClient.maxConnectionsPerHost = 2; // Limit for background tasks
      
      final transport = connect_protocol.Transport(
        baseUrl: ApiConfig.chatBaseUrl,
        codec: const connect_protobuf.ProtoCodec(),
        httpClient: connect_io.createHttpClient(httpClient),
      );
      final chatClient = ChatServiceClient(transport);

      // Process pending jobs
      final success = await _processPendingJobs(
        jobRepo,
        messageRepo,
        chatClient,
        authHeaders,
      );

      AppLogger.info('Background sync completed', data: {'success': success});
      return success;
    } catch (e, stack) {
      AppLogger.error(
        'Background sync task failed',
        error: e,
        stackTrace: stack,
      );
      return false; // Signal failure so workmanager can retry
    }
  }

  /// Process all pending upload jobs
  static Future<bool> _processPendingJobs(
    PendingJobRepository jobRepo,
    MessageRepository messageRepo,
    ChatServiceClient chatClient,
    connect.Headers authHeaders,
  ) async {
    try {
      final jobs = await jobRepo.getPendingJobs();

      if (jobs.isEmpty) {
        AppLogger.debug('No pending jobs to process in background sync');
        return true;
      }

      AppLogger.info(
        'Processing pending jobs in background',
        data: {'jobCount': jobs.length},
      );

      for (final job in jobs) {
        try {
          await _processJob(job, chatClient, messageRepo, jobRepo, authHeaders);
        } catch (e, stackTrace) {
          AppLogger.error(
            'Failed to process background job',
            error: e,
            stackTrace: stackTrace,
            data: {'jobId': job.id, 'jobType': job.type.toString()},
          );
          // Continue with other jobs even if one fails
        }
      }

      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error processing pending jobs',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Process a single job
  static Future<void> _processJob(
    PendingJob job,
    ChatServiceClient chatClient,
    MessageRepository messageRepo,
    PendingJobRepository jobRepo,
    connect.Headers authHeaders,
  ) async {
    switch (job.type) {
      case JobType.sendMessage:
        await _processSendMessage(job, chatClient, messageRepo, authHeaders);
        break;
      default:
        AppLogger.debug(
          'Skipping unsupported job type in background',
          data: {'jobType': job.type.toString()},
        );
        return; // Skip unknown/unsupported jobs
    }

    // Mark job as completed
    await jobRepo.deleteJob(job.id);
    AppLogger.debug(
      'Background job completed',
      data: {'jobId': job.id, 'jobType': job.type.toString()},
    );
  }

  /// Send a message
  static Future<void> _processSendMessage(
    PendingJob job,
    ChatServiceClient chatClient,
    MessageRepository messageRepo,
    connect.Headers authHeaders,
  ) async {
    final payload = job.payload;

    // Convert content Map to Struct
    final contentStruct = _mapToStruct(
      payload['content'] as Map<String, dynamic>,
    );

    // Create timestamp
    final now = DateTime.now();
    final timestamp = google_timestamp.Timestamp(
      seconds: fixnum.Int64(now.millisecondsSinceEpoch ~/ 1000),
      nanos: (now.millisecondsSinceEpoch % 1000) * 1000000,
    );

    final event = pb.RoomEvent(
      id: payload['localId'] as String? ?? '',
      roomId: payload['roomId'] as String,
      senderId: 'current_user_id', // TODO: Get from auth service
      type: _mapLocalEventTypeToProto(
        RoomEventType.values.firstWhere(
          (t) => t.toString() == payload['type'],
          orElse: () => RoomEventType.text,
        ),
      ),
      payload: contentStruct,
      sentAt: timestamp,
    );

    final request = pb.SendEventRequest(event: [event]);
    final response = await chatClient.sendEvent(request, headers: authHeaders);

    // Update local message status
    if (payload['localId'] != null && response.ack.isNotEmpty) {
      final ackEventId = response.ack.first.eventId;
      await messageRepo.updateMessageStatus(ackEventId, EventStatus.sent);
      AppLogger.debug(
        'Message sent in background',
        data: {'localId': payload['localId'], 'serverId': ackEventId},
      );
    }
  }

  // Helper methods for Struct conversion (copied from SyncEngine)

  static google_struct.Struct _mapToStruct(Map<String, dynamic> map) {
    final struct = google_struct.Struct();
    for (final entry in map.entries) {
      struct.fields[entry.key] = _objectToValue(entry.value);
    }
    return struct;
  }

  static google_struct.Value _objectToValue(dynamic obj) {
    final value = google_struct.Value();

    if (obj == null) {
      value.nullValue = google_struct.NullValue.NULL_VALUE;
    } else if (obj is bool) {
      value.boolValue = obj;
    } else if (obj is num) {
      value.numberValue = obj.toDouble();
    } else if (obj is String) {
      value.stringValue = obj;
    } else if (obj is List) {
      value.listValue = google_struct.ListValue(
        values: obj.map(_objectToValue).toList(),
      );
    } else if (obj is Map<String, dynamic>) {
      value.structValue = _mapToStruct(obj);
    } else {
      value.stringValue = obj.toString();
    }

    return value;
  }

  static pb.RoomEventType _mapLocalEventTypeToProto(RoomEventType type) {
    switch (type) {
      case RoomEventType.text:
        return pb.RoomEventType.ROOM_EVENT_TYPE_TEXT;
      case RoomEventType.image:
      case RoomEventType.video:
      case RoomEventType.audio:
      case RoomEventType.file:
        return pb.RoomEventType.ROOM_EVENT_TYPE_ATTACHMENT;
      case RoomEventType.reaction:
        return pb.RoomEventType.ROOM_EVENT_TYPE_REACTION;
      case RoomEventType.callOffer:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_OFFER;
      case RoomEventType.callAnswer:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ANSWER;
      case RoomEventType.callIce:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ICE;
      case RoomEventType.callEnd:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_END;
      case RoomEventType.motion:
      case RoomEventType.vote:
      case RoomEventType.transaction:
        return pb.RoomEventType.ROOM_EVENT_TYPE_TEXT;
    }
  }
}
