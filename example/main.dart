import 'dart:io';

import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:signalr_core/signalr_core.dart';

// main() async {

//   HttpClient client = HttpClient();
//     client.badCertificateCallback = ((X509Certificate cert, String host, int port) => true);
//     BaseClient c = IOClient(client);

//   final connection = HubConnectionBuilder()

//       .withUrl(
//           'https://localhost:5001/chatHub',
//           HttpConnectionOptions(
//             client: c,
//             transport: HttpTransportType.webSockets,
//             logging: (level, message) => print(message),
//           ))
//       .withAutomaticReconnect()
//       .build();

//   await connection.start();

//   connection.on('ReceiveMessage', (message) {
//     print(message.toString());
//   });

//   connection.onreconnecting((e) {
//     print('Reconnecting yo');
//   });

//   await connection.invoke('SendMessage', args: ['Bob', 'Says hi!']);
// }

void main(List<String> arguments) async {
  final connection = HubConnectionBuilder()
      .withUrl(
          'https://jamiewest.dev/chatHub',
          //'https://scrumpokertest.azurewebsites.net/scrum-poker',
          //'https://webapplication220200223011431.azurewebsites.net/chatHub',
          HttpConnectionOptions(
            transport: HttpTransportType.webSockets,
            logging: (level, message) => print(message),
          ))
      .withAutomaticReconnect()
      .build();

  await connection.start();

  connection.on('ReceiveMessage', (message) {
    print(message.toString());
  });

  connection.onclose((e) => print('----------------------- Closed -----------------------'));
  connection.onreconnecting((e) => print('----------------------- Reconnecting -----------------------'));
  connection.onreconnected((s) => print('----------------------- Reconnected -----------------------'));
}