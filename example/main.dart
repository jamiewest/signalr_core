import 'dart:io';

import 'package:http/io_client.dart';
import 'package:signalr_core/signalr_core.dart';

Future<void> main(List<String> arguments) async {
 final connection = HubConnectionBuilder().withUrl('http://localhost:5000/chatHub', 
    HttpConnectionOptions(
      accessTokenFactory: () => Future.value('test'),
      client: IOClient(HttpClient()..badCertificateCallback = (x, y, z) => true),
        logging: (level, message) => print(message),
    )).build();
 
await connection.start();

connection.on('ReceiveMessage', (message) {
    print(message.toString());
});

await connection.invoke('SendMessage', args: ['Bob', 'Says hi!']);
}
