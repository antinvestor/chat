import 'dart:convert';
import '../db/database.dart';
import 'pending_job.dart';

class PendingJobRepository {
  final AppDatabase _database;

  PendingJobRepository(this._database);

  Future<void> addJob(JobType type, Map<String, dynamic> payload) async {
    final db = await _database.database;
    db.execute(
      'INSERT INTO pending_jobs (type, payload, created_at) VALUES (?, ?, ?)',
      [type.name, jsonEncode(payload), DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<List<PendingJob>> getPendingJobs() async {
    final db = await _database.database;
    final results = db.select(
      "SELECT * FROM pending_jobs WHERE status = 'pending' ORDER BY created_at ASC",
    );

    return results.map((row) {
      return PendingJob(
        id: row['id'] as int,
        type: JobType.values.firstWhere((e) => e.name == row['type']),
        payload: jsonDecode(row['payload'] as String),
        createdAt: row['created_at'] as int,
        retryCount: row['retry_count'] as int,
        status: row['status'] as String,
      );
    }).toList();
  }

  Future<void> deleteJob(int id) async {
    final db = await _database.database;
    db.execute('DELETE FROM pending_jobs WHERE id = ?', [id]);
  }

  Future<void> incrementRetry(int id) async {
    final db = await _database.database;
    db.execute(
      'UPDATE pending_jobs SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }
}
