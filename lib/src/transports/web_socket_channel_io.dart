import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> connect(Uri uri, {BaseClient client}) async {
  Random random = Random();

  Uint8List nonceData = Uint8List(16);
  for (int i = 0; i < 16; i++) {
    nonceData[i] = random.nextInt(256);
  }
  String nonce = base64.encode(nonceData);

  WebSocket ws;

  var ws_uri = Uri(
      scheme: uri.scheme == "wss" ? "https" : "http",
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.port,
      path: uri.path,
      query: uri.query,
      fragment: uri.fragment);

  var request = Request('GET', ws_uri)
    ..headers.addAll({
      'Connection': 'Upgrade',
      'Upgrade': 'websocket',
      'Sec-WebSocket-Key': nonce,
      'Cache-Control': 'no-cache',
      'Sec-WebSocket-Version': '13'
    });

  var response = await client.send(request);
  Socket socket = await (response as IOStreamedResponse).detachSocket();

  ws = WebSocket.fromUpgradedSocket(
    socket,
    serverSide: false,
  );

  return IOWebSocketChannel(ws);
}
