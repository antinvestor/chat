import 'dart:io' as io;
import 'package:connectrpc/connect.dart' as connect;
import 'package:connectrpc/protocol/connect.dart' as connect_protocol;
import 'package:connectrpc/protobuf.dart' as connect_protobuf;
import 'package:connectrpc/io.dart' as connect_io;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../apis/chat/v1/chat.connect.client.dart';

final networkClientProvider = Provider<connect.Transport>((ref) {
  // TODO: Move to environment config
  const baseUrl = 'https://api.antinvestor.com';
  
  return connect_protocol.Transport(
    baseUrl: baseUrl,
    codec: const connect_protobuf.ProtoCodec(),
    httpClient: connect_io.createHttpClient(io.HttpClient()),
  );
});

final chatServiceClientProvider = Provider<ChatServiceClient>((ref) {
  final client = ref.watch(networkClientProvider);
  return ChatServiceClient(client);
});

final gatewayServiceClientProvider = Provider<GatewayServiceClient>((ref) {
  final client = ref.watch(networkClientProvider);
  return GatewayServiceClient(client);
});
