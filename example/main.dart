import 'package:signalr_core/signalr_core.dart';

main() async {
  final connection = HubConnectionBuilder()
      .withUrl(
          'http://localhost:5000/chatHub',
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

  connection.onreconnecting((e) {
    print('Reconnecting yo');
  });

  await connection.invoke('SendMessage', args: ['Bob', 'Says hi!']);
}
