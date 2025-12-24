import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xid/xid.dart';

import '../../../core/sync/sync_engine.dart';
import '../../messages/domain/room_event.dart';

final transactionServiceProvider = FutureProvider<TransactionService>((ref) async {
  final syncEngine = await ref.watch(syncEngineProvider.future);
  return TransactionService(syncEngine);
});

class TransactionService {
  final SyncEngine _syncEngine;

  TransactionService(this._syncEngine);

  Future<void> sendMoney({
    required String roomId,
    required String recipientId,
    required double amount,
    required String currency,
    String? note,
  }) async {
    final content = {
      'recipientId': recipientId,
      'amount': amount,
      'currency': currency,
      'note': note,
      'status': 'pending', // pending, completed, failed
    };

    final event = RoomEvent(
      id: Xid().toString(),
      roomId: roomId,
      senderId: 'current_user_id', // TODO: Get from auth
      type: RoomEventType.transaction,
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      localId: Xid().toString(),
    );

    await _syncEngine.sendSignal(event);
  }
}
