import 'package:http/http.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> connect(Uri uri, {BaseClient? client}) async =>
    Future.value(WebSocketChannel.connect(uri));
