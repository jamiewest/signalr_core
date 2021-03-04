import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> connect(
  Uri uri, {
  required BaseClient client,
}) async {
  var random = Random();

  var nonceData = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    nonceData[i] = random.nextInt(256);
  }
  var nonce = base64.encode(nonceData);

  WebSocket ws;

  var wsUri = Uri(
      scheme: uri.scheme == 'wss' ? 'https' : 'http',
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.port,
      path: uri.path,
      query: uri.query,
      fragment: uri.fragment);

  var request = Request('GET', wsUri)
    ..headers.addAll({
      'Connection': 'Upgrade',
      'Upgrade': 'websocket',
      'Sec-WebSocket-Key': nonce,
      'Cache-Control': 'no-cache',
      'Sec-WebSocket-Version': '13',
    });

  var response = await client.send(request);
  var socket = await (response as IOStreamedResponse).detachSocket();

  ws = WebSocket.fromUpgradedSocket(
    socket,
    serverSide: false,
  );

  return IOWebSocketChannel(ws);
}
