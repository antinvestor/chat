import 'package:freezed_annotation/freezed_annotation.dart';

part 'pending_job.freezed.dart';
part 'pending_job.g.dart';

enum JobType {
  sendMessage,
  sendMediaMessage,
  editMessage,
  uploadFile,
  createRoom,
  updateRoom,
  deleteRoom,
  addRoomMembers,
  removeRoomMembers,
  leaveRoom,
  vote,
  syncContacts,
}

@freezed
abstract class PendingJob with _$PendingJob {
  const factory PendingJob({
    required int id,
    required JobType type,
    required Map<String, dynamic> payload,
    required int createdAt,
    @Default(0) int retryCount,
    @Default('pending') String status,
  }) = _PendingJob;

  factory PendingJob.fromJson(Map<String, dynamic> json) =>
      _$PendingJobFromJson(json);
}
