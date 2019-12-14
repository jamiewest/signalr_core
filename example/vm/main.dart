import 'dart:async';

import 'package:signalr/signalr.dart';

main() async {

  final connection = HubConnectionBuilder().withUrl('http://localhost:5000/asyncEnumerableHub', 
    HttpConnectionOptions(
      logging: (level, message) => print(message),
    )).build();
 
  await connection.start();

  connection.on('ReceiveMessage', (stuff) {
    print(stuff.toString());
  });

  await connection.invoke('SendMessage', args: ['Bob', 'Says hi!']);

  final stream = connection.stream<int>('Counter', args: [50,100]);

  stream.listen((data) {
    print(data); 
  });

  var s = StreamController<String>();

  await connection.send(methodName: 'UploadStream', args: [s.stream]);

  s.add('1');
  s.add('2');
  s.add('3');


  
}
