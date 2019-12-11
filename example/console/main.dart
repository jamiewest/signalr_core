import 'package:signalr/signalr.dart';

main() async {

  final connection = HubConnectionBuilder().withUrl('http://localhost:5000/chatHub', 
    HttpConnectionOptions(
      logging: (level, message) => print(message),
    )).build();
 
  await connection.start();

  connection.on('ReceiveMessage', (stuff) {
    print(stuff.toString());
  });

  await connection.invoke('SendMessage', args: ['duky', 'duke']);
}
