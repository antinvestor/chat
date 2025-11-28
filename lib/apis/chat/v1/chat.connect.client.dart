//
//  Generated code. Do not modify.
//  source: chat/v1/chat.proto
//

import "package:connectrpc/connect.dart" as connect_rpc;
import "chat.pb.dart" as chatv1chat;
import "chat.connect.spec.dart" as specs;

extension type GatewayServiceClient (connect_rpc.Transport _transport) {
  /// Bi-directional, long-lived connection. Client sends ConnectRequest (initial auth + acks/commands).
  /// Server streams ConnectResponse objects in chronological order for rooms the client is subscribed to.
  /// Stream resume: client may provide last_received_event_id or resume_token to continue after reconnect.
  Stream<chatv1chat.ConnectResponse> connect(
    Stream<chatv1chat.ConnectRequest> input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).bidi(
      specs.GatewayService.connect,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }
}
extension type ChatServiceClient (connect_rpc.Transport _transport) {
  /// Send an event (unified message model). Idempotent if idempotency_key is provided.
  Future<chatv1chat.SendEventResponse> sendEvent(
    chatv1chat.SendEventRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.sendEvent,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Fetch history for a room. Cursor-based paging (cursor = opaque server token).
  Future<chatv1chat.GetHistoryResponse> getHistory(
    chatv1chat.GetHistoryRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.getHistory,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Room lifecycle & management
  Future<chatv1chat.CreateRoomResponse> createRoom(
    chatv1chat.CreateRoomRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.createRoom,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Stream<chatv1chat.SearchRoomsResponse> searchRooms(
    chatv1chat.SearchRoomsRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).server(
      specs.ChatService.searchRooms,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<chatv1chat.UpdateRoomResponse> updateRoom(
    chatv1chat.UpdateRoomRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.updateRoom,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<chatv1chat.DeleteRoomResponse> deleteRoom(
    chatv1chat.DeleteRoomRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.deleteRoom,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Subscriptionship & roles
  Future<chatv1chat.AddRoomSubscriptionsResponse> addRoomSubscriptions(
    chatv1chat.AddRoomSubscriptionsRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.addRoomSubscriptions,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<chatv1chat.RemoveRoomSubscriptionsResponse> removeRoomSubscriptions(
    chatv1chat.RemoveRoomSubscriptionsRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.removeRoomSubscriptions,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<chatv1chat.UpdateSubscriptionRoleResponse> updateSubscriptionRole(
    chatv1chat.UpdateSubscriptionRoleRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.updateSubscriptionRole,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  Future<chatv1chat.SearchRoomSubscriptionsResponse> searchRoomSubscriptions(
    chatv1chat.SearchRoomSubscriptionsRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.searchRoomSubscriptions,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Update different states that the client can be in for room subscriptions awareness
  Future<chatv1chat.UpdateClientStateResponse> updateClientState(
    chatv1chat.UpdateClientStateRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.updateClientState,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }

  /// Get client state for a set of profiles in a room
  Future<chatv1chat.GetClientStateResponse> getClientState(
    chatv1chat.GetClientStateRequest input, {
    connect_rpc.Headers? headers,
    connect_rpc.AbortSignal? signal,
    Function(connect_rpc.Headers)? onHeader,
    Function(connect_rpc.Headers)? onTrailer,
  }) {
    return connect_rpc.Client(_transport).unary(
      specs.ChatService.getClientState,
      input,
      signal: signal,
      headers: headers,
      onHeader: onHeader,
      onTrailer: onTrailer,
    );
  }
}
