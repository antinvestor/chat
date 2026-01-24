import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'pending_job.dart' as domain;

class PendingJobRepository {
  PendingJobRepository(this._database);
  final AppDatabase _database;

  // Retry backoff configuration
  static const _initialRetryDelayMs = 1000; // 1 second
  static const _maxRetryDelayMs = 300000; // 5 minutes
  static const _maxRetries = 5;

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
    final now = DateTime.now().millisecondsSinceEpoch;
    final query = _database.select(_database.pendingJobs)
      ..where(
        (t) =>
            t.status.equals('pending') &
            // Only get jobs ready for processing (nextRetryAt is null or in the past)
            (t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerOrEqualValue(now)),
      )
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
            nextRetryAt: row.nextRetryAt,
          ),
        )
        .toList();
  }

  /// Watch for pending jobs reactively
  /// Emits whenever jobs are added, modified, or deleted
  /// Only returns jobs that are ready for processing (nextRetryAt has passed)
  Stream<List<domain.PendingJob>> watchPendingJobs() {
    final query = _database.select(_database.pendingJobs)
      ..where((t) => t.status.equals('pending'))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    return query.watch().map((results) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return results
          .where((row) => row.nextRetryAt == null || row.nextRetryAt! <= now)
          .map(
            (row) => domain.PendingJob(
              id: row.id,
              type: domain.JobType.values.firstWhere((e) => e.name == row.type),
              payload: row.payload != null ? jsonDecode(row.payload!) : {},
              createdAt: row.createdAt ?? 0,
              retryCount: row.retryCount,
              status: row.status,
              nextRetryAt: row.nextRetryAt,
            ),
          )
          .toList();
    });
  }

  /// Check if there are any pending jobs ready for processing
  Future<bool> hasPendingJobs() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final query = _database.selectOnly(_database.pendingJobs)
      ..where(
        _database.pendingJobs.status.equals('pending') &
            (_database.pendingJobs.nextRetryAt.isNull() |
                _database.pendingJobs.nextRetryAt.isSmallerOrEqualValue(now)),
      )
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

  /// Increment retry count and set next retry time with exponential backoff
  /// Returns true if job can still be retried, false if max retries reached
  Future<bool> incrementRetry(int id) async {
    // Get current retry count
    final job = await (_database.select(
      _database.pendingJobs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();

    if (job == null) return false;

    final newRetryCount = job.retryCount + 1;

    if (newRetryCount >= _maxRetries) {
      // Mark as failed instead of deleting - preserves history
      await (_database.update(_database.pendingJobs)
            ..where((t) => t.id.equals(id)))
          .write(const PendingJobsCompanion(status: Value('failed')));
      return false;
    }

    // Calculate next retry time with exponential backoff + jitter
    final baseDelay = _initialRetryDelayMs * (1 << newRetryCount);
    final cappedDelay = min(baseDelay, _maxRetryDelayMs);
    final jitter = Random().nextInt(cappedDelay ~/ 4); // 0-25% jitter
    final nextRetryAt =
        DateTime.now().millisecondsSinceEpoch + cappedDelay + jitter;

    await (_database.update(
      _database.pendingJobs,
    )..where((t) => t.id.equals(id))).write(
      PendingJobsCompanion(
        retryCount: Value(newRetryCount),
        nextRetryAt: Value(nextRetryAt),
      ),
    );

    return true;
  }

  /// Get count of failed jobs for monitoring
  Future<int> getFailedJobCount() async {
    final query = _database.selectOnly(_database.pendingJobs)
      ..where(_database.pendingJobs.status.equals('failed'))
      ..addColumns([_database.pendingJobs.id.count()]);
    final result = await query.getSingle();
    return result.read(_database.pendingJobs.id.count()) ?? 0;
  }

  /// Clear old failed jobs (older than specified duration)
  Future<int> clearOldFailedJobs({
    Duration maxAge = const Duration(days: 7),
  }) async {
    final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    return (_database.delete(_database.pendingJobs)..where(
          (t) =>
              t.status.equals('failed') &
              t.createdAt.isSmallerOrEqualValue(cutoff),
        ))
        .go();
  }
}
