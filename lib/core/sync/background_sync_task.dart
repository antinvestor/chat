import 'dart:io' as io;

import 'package:antinvestor_api_chat/antinvestor_api_chat.dart' as pb;
import 'package:antinvestor_api_chat/antinvestor_api_chat.dart';
import 'package:antinvestor_api_common/antinvestor_api_common.dart' as common;
import 'package:connectrpc/connect.dart' as connect;
import 'package:connectrpc/io.dart' as connect_io;
import 'package:connectrpc/protobuf.dart' as connect_protobuf;
import 'package:connectrpc/protocol/connect.dart' as connect_protocol;
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/messages/data/message_repository.dart';
import '../../features/messages/domain/room_event.dart' as domain;
import '../db/database.dart';
import '../logging/app_logger.dart';
import '../networking/api_config.dart';
import 'pending_job.dart' as domain_job;
import 'pending_job_repository.dart';

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
    domain_job.PendingJob job,
    ChatServiceClient chatClient,
    MessageRepository messageRepo,
    PendingJobRepository jobRepo,
    connect.Headers authHeaders,
  ) async {
    switch (job.type) {
      case domain_job.JobType.sendMessage:
      case domain_job.JobType.sendMediaMessage:
        await _processSendMessage(job, chatClient, messageRepo, authHeaders);
        break;
      case domain_job.JobType.createRoom:
        await _processCreateRoom(job, chatClient, authHeaders);
        break;
      case domain_job.JobType.updateRoom:
        await _processUpdateRoom(job, chatClient, authHeaders);
        break;
      case domain_job.JobType.deleteRoom:
        await _processDeleteRoom(job, chatClient, authHeaders);
        break;
      case domain_job.JobType.addRoomMembers:
        await _processAddRoomMembers(job, chatClient, authHeaders);
        break;
      case domain_job.JobType.removeRoomMembers:
        await _processRemoveRoomMembers(job, chatClient, authHeaders);
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

  /// Create a room
  static Future<void> _processCreateRoom(
    domain_job.PendingJob job,
    ChatServiceClient chatClient,
    connect.Headers authHeaders,
  ) async {
    final payload = job.payload;

    final request = pb.CreateRoomRequest(
      id: payload['id'] as String,
      name: payload['name'] as String? ?? '',
      description: payload['description'] as String? ?? '',
      isPrivate: payload['isPrivate'] as bool? ?? false,
      members: (payload['members'] as List<dynamic>?)?.cast<String>() ?? [],
    );

    if (payload['metadata'] != null) {
      request.metadata = _mapToStruct(
        payload['metadata'] as Map<String, dynamic>,
      );
    }

    final response = await chatClient.createRoom(request, headers: authHeaders);

    if (response.hasRoom()) {
      AppLogger.debug('Room created in background', data: {
        'localId': payload['id'],
        'serverId': response.room.id,
      });
    } else if (response.hasError()) {
      throw Exception('Room creation failed: ${response.error.message}');
    }
  }

  /// Update a room
  static Future<void> _processUpdateRoom(
    domain_job.PendingJob job,
    ChatServiceClient chatClient,
    connect.Headers authHeaders,
  ) async {
    final payload = job.payload;

    final request = pb.UpdateRoomRequest(
      roomId: payload['id'] as String,
      name: payload['name'] as String? ?? '',
      topic: payload['description'] as String? ?? '',
    );

    if (payload['metadata'] != null) {
      request.metadata = _mapToStruct(
        payload['metadata'] as Map<String, dynamic>,
      );
    }

    await chatClient.updateRoom(request, headers: authHeaders);
    AppLogger.debug('Room updated in background', data: {'roomId': payload['id']});
  }

  /// Delete a room
  static Future<void> _processDeleteRoom(
    domain_job.PendingJob job,
    ChatServiceClient chatClient,
    connect.Headers authHeaders,
  ) async {
    final payload = job.payload;

    final request = pb.DeleteRoomRequest(
      roomId: payload['id'] as String,
    );

    await chatClient.deleteRoom(request, headers: authHeaders);
    AppLogger.debug('Room deleted in background', data: {'roomId': payload['id']});
  }

  /// Add members to a room
  static Future<void> _processAddRoomMembers(
    domain_job.PendingJob job,
    ChatServiceClient chatClient,
    connect.Headers authHeaders,
  ) async {
    final payload = job.payload;
    final roomId = payload['roomId'] as String;
    final profileIds = (payload['profileIds'] as List<dynamic>).cast<String>();

    // Convert profileIds to RoomSubscription objects
    final members = profileIds.map((profileId) => pb.RoomSubscription(
      roomId: roomId,
      profileId: profileId,
    )).toList();

    final request = pb.AddRoomSubscriptionsRequest(
      roomId: roomId,
      members: members,
    );

    await chatClient.addRoomSubscriptions(request, headers: authHeaders);
    AppLogger.debug('Members added in background', data: {
      'roomId': roomId,
      'memberCount': profileIds.length,
    });
  }

  /// Remove members from a room
  static Future<void> _processRemoveRoomMembers(
    domain_job.PendingJob job,
    ChatServiceClient chatClient,
    connect.Headers authHeaders,
  ) async {
    final payload = job.payload;

    final request = pb.RemoveRoomSubscriptionsRequest(
      roomId: payload['roomId'] as String,
      profileIds: (payload['profileIds'] as List<dynamic>).cast<String>(),
    );

    await chatClient.removeRoomSubscriptions(request, headers: authHeaders);
    AppLogger.debug('Members removed in background', data: {
      'roomId': payload['roomId'],
      'memberCount': (payload['profileIds'] as List).length,
    });
  }

  /// Send a message
  static Future<void> _processSendMessage(
    domain_job.PendingJob job,
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
    final timestamp = common.Timestamp(
      seconds: fixnum.Int64(now.millisecondsSinceEpoch ~/ 1000),
      nanos: (now.millisecondsSinceEpoch % 1000) * 1000000,
    );

    final event = pb.RoomEvent(
      id: payload['localId'] as String? ?? '',
      roomId: payload['roomId'] as String,
      senderId: 'current_user_id', // TODO: Get from auth service
      type: _mapLocalEventTypeToProto(
        domain.RoomEventType.values.firstWhere(
          (t) => t.toString() == payload['type'],
          orElse: () => domain.RoomEventType.text,
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
      await messageRepo.updateMessageStatus(ackEventId, domain.EventStatus.sent);
      AppLogger.debug(
        'Message sent in background',
        data: {'localId': payload['localId'], 'serverId': ackEventId},
      );
    }
  }

  // Helper methods for Struct conversion (copied from SyncEngine)

  static common.Struct _mapToStruct(Map<String, dynamic> map) {
    final struct = common.Struct();
    for (final entry in map.entries) {
      struct.fields[entry.key] = _objectToValue(entry.value);
    }
    return struct;
  }

  static common.Value _objectToValue(dynamic obj) {
    final value = common.Value();

    if (obj == null) {
      value.nullValue = common.NullValue.NULL_VALUE;
    } else if (obj is bool) {
      value.boolValue = obj;
    } else if (obj is num) {
      value.numberValue = obj.toDouble();
    } else if (obj is String) {
      value.stringValue = obj;
    } else if (obj is List) {
      value.listValue = common.ListValue(
        values: obj.map(_objectToValue).toList(),
      );
    } else if (obj is Map<String, dynamic>) {
      value.structValue = _mapToStruct(obj);
    } else {
      value.stringValue = obj.toString();
    }

    return value;
  }

  static pb.RoomEventType _mapLocalEventTypeToProto(domain.RoomEventType type) {
    switch (type) {
      case domain.RoomEventType.text:
        return pb.RoomEventType.ROOM_EVENT_TYPE_TEXT;
      case domain.RoomEventType.image:
      case domain.RoomEventType.video:
      case domain.RoomEventType.audio:
      case domain.RoomEventType.file:
        return pb.RoomEventType.ROOM_EVENT_TYPE_ATTACHMENT;
      case domain.RoomEventType.reaction:
        return pb.RoomEventType.ROOM_EVENT_TYPE_REACTION;
      case domain.RoomEventType.callOffer:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_OFFER;
      case domain.RoomEventType.callAnswer:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ANSWER;
      case domain.RoomEventType.callIce:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ICE;
      case domain.RoomEventType.callEnd:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_END;
      case domain.RoomEventType.motion:
      case domain.RoomEventType.vote:
      case domain.RoomEventType.transaction:
        return pb.RoomEventType.ROOM_EVENT_TYPE_TEXT;
    }
  }
}
