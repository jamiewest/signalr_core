import 'package:http/http.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> connect(Uri uri, {BaseClient? client}) => Future.error(
    UnsupportedError('No implementation of the connect api provided'));
