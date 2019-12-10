//import '../../lib/signalr.dart';
import 'package:signalr/signalr.dart';

main() async {
  var x = HttpConnectionOptions(
    logging: (l,m) => print(m),
    transport: HttpTransportType.webSockets,
    skipNegotiation: true
  );

  final connection = HubConnectionBuilder().withUrl('http://localhost:5000/chatHub', x).build();


  // var connection = HubConnection.withUrl(
  //   url: 'http://localhost:5000/chatHub', 
  //   options: HttpConnectionOptions(
  //     transport: HttpTransportType.serverSentEvents, 
  //     logging: (level, message) {
  //       print(message);
  //     },
  //     logMessageContent: false));
  
  await connection.start();

  connection.on('ReceiveMessage', (stuff) {
    print(stuff.toString());
  });

  await connection.invoke('SendMessage', args: ['duky', 'duke']);
}
