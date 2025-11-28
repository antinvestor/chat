//
//  Generated code. Do not modify.
//  source: chat/v1/chat.proto
//

import "package:connectrpc/connect.dart" as connect_rpc;
import "chat.pb.dart" as chatv1chat;

abstract final class GatewayService {
  /// Fully-qualified name of the GatewayService service.
  static const name = 'chat.v1.GatewayService';

  /// Bi-directional, long-lived connection. Client sends ConnectRequest (initial auth + acks/commands).
  /// Server streams ConnectResponse objects in chronological order for rooms the client is subscribed to.
  /// Stream resume: client may provide last_received_event_id or resume_token to continue after reconnect.
  static const connect = connect_rpc.Spec(
    '/$name/Connect',
    connect_rpc.StreamType.bidi,
    chatv1chat.ConnectRequest.new,
    chatv1chat.ConnectResponse.new,
  );
}
abstract final class ChatService {
  /// Fully-qualified name of the ChatService service.
  static const name = 'chat.v1.ChatService';

  /// Send an event (unified message model). Idempotent if idempotency_key is provided.
  static const sendEvent = connect_rpc.Spec(
    '/$name/SendEvent',
    connect_rpc.StreamType.unary,
    chatv1chat.SendEventRequest.new,
    chatv1chat.SendEventResponse.new,
  );

  /// Fetch history for a room. Cursor-based paging (cursor = opaque server token).
  static const getHistory = connect_rpc.Spec(
    '/$name/GetHistory',
    connect_rpc.StreamType.unary,
    chatv1chat.GetHistoryRequest.new,
    chatv1chat.GetHistoryResponse.new,
  );

  /// Room lifecycle & management
  static const createRoom = connect_rpc.Spec(
    '/$name/CreateRoom',
    connect_rpc.StreamType.unary,
    chatv1chat.CreateRoomRequest.new,
    chatv1chat.CreateRoomResponse.new,
  );

  static const searchRooms = connect_rpc.Spec(
    '/$name/SearchRooms',
    connect_rpc.StreamType.server,
    chatv1chat.SearchRoomsRequest.new,
    chatv1chat.SearchRoomsResponse.new,
  );

  static const updateRoom = connect_rpc.Spec(
    '/$name/UpdateRoom',
    connect_rpc.StreamType.unary,
    chatv1chat.UpdateRoomRequest.new,
    chatv1chat.UpdateRoomResponse.new,
  );

  static const deleteRoom = connect_rpc.Spec(
    '/$name/DeleteRoom',
    connect_rpc.StreamType.unary,
    chatv1chat.DeleteRoomRequest.new,
    chatv1chat.DeleteRoomResponse.new,
  );

  /// Subscriptionship & roles
  static const addRoomSubscriptions = connect_rpc.Spec(
    '/$name/AddRoomSubscriptions',
    connect_rpc.StreamType.unary,
    chatv1chat.AddRoomSubscriptionsRequest.new,
    chatv1chat.AddRoomSubscriptionsResponse.new,
  );

  static const removeRoomSubscriptions = connect_rpc.Spec(
    '/$name/RemoveRoomSubscriptions',
    connect_rpc.StreamType.unary,
    chatv1chat.RemoveRoomSubscriptionsRequest.new,
    chatv1chat.RemoveRoomSubscriptionsResponse.new,
  );

  static const updateSubscriptionRole = connect_rpc.Spec(
    '/$name/UpdateSubscriptionRole',
    connect_rpc.StreamType.unary,
    chatv1chat.UpdateSubscriptionRoleRequest.new,
    chatv1chat.UpdateSubscriptionRoleResponse.new,
  );

  static const searchRoomSubscriptions = connect_rpc.Spec(
    '/$name/SearchRoomSubscriptions',
    connect_rpc.StreamType.unary,
    chatv1chat.SearchRoomSubscriptionsRequest.new,
    chatv1chat.SearchRoomSubscriptionsResponse.new,
  );

  /// Update different states that the client can be in for room subscriptions awareness
  static const updateClientState = connect_rpc.Spec(
    '/$name/UpdateClientState',
    connect_rpc.StreamType.unary,
    chatv1chat.UpdateClientStateRequest.new,
    chatv1chat.UpdateClientStateResponse.new,
  );

  /// Get client state for a set of profiles in a room
  static const getClientState = connect_rpc.Spec(
    '/$name/GetClientState',
    connect_rpc.StreamType.unary,
    chatv1chat.GetClientStateRequest.new,
    chatv1chat.GetClientStateResponse.new,
  );
}
