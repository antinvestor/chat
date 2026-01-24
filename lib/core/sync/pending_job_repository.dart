import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'pending_job.dart' as domain;

class PendingJobRepository {
  PendingJobRepository(this._database);
  final AppDatabase _database;

  Future<void> addJob(domain.JobType type, Map<String, dynamic> payload) async {
    await _database
        .into(_database.pendingJobs)
        .insert(
          PendingJobsCompanion.insert(
            type: type.name,
            payload: Value(jsonEncode(payload)),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  Future<List<domain.PendingJob>> getPendingJobs() async {
    final query = _database.select(_database.pendingJobs)
      ..where((t) => t.status.equals('pending'))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    final results = await query.get();

    return results
        .map(
          (row) => domain.PendingJob(
            id: row.id,
            type: domain.JobType.values.firstWhere((e) => e.name == row.type),
            payload: row.payload != null ? jsonDecode(row.payload!) : {},
            createdAt: row.createdAt ?? 0,
            retryCount: row.retryCount,
            status: row.status,
          ),
        )
        .toList();
  }

  /// Watch for pending jobs reactively
  /// Emits whenever jobs are added, modified, or deleted
  Stream<List<domain.PendingJob>> watchPendingJobs() {
    final query = _database.select(_database.pendingJobs)
      ..where((t) => t.status.equals('pending'))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    return query.watch().map(
      (results) => results
          .map(
            (row) => domain.PendingJob(
              id: row.id,
              type: domain.JobType.values.firstWhere((e) => e.name == row.type),
              payload: row.payload != null ? jsonDecode(row.payload!) : {},
              createdAt: row.createdAt ?? 0,
              retryCount: row.retryCount,
              status: row.status,
            ),
          )
          .toList(),
    );
  }

  /// Check if there are any pending jobs without fetching all data
  Future<bool> hasPendingJobs() async {
    final query = _database.selectOnly(_database.pendingJobs)
      ..where(_database.pendingJobs.status.equals('pending'))
      ..addColumns([_database.pendingJobs.id])
      ..limit(1);
    final result = await query.get();
    return result.isNotEmpty;
  }

  Future<void> deleteJob(int id) async {
    await (_database.delete(
      _database.pendingJobs,
    )..where((t) => t.id.equals(id))).go();
  }

  Future<void> incrementRetry(int id) async {
    await _database.customStatement(
      'UPDATE pending_jobs SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }
}
