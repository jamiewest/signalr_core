import 'package:signalr_core/signalr_core.dart';

main() {
  final connection = HubConnectionBuilder().withUrl('http://localhost:5000/chatHub', 
    HttpConnectionOptions(
      transport: HttpTransportType.serverSentEvents,
      logging: (level, message) => print(message),
    )).build();
 
  connection.start().then((_) {
    connection.on('ReceiveMessage', (message) {
      print(message.toString());
    });

    connection.invoke('SendMessage', args: ['Bob', 'Says hi!']);
  });
}
