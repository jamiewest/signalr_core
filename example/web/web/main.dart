import 'dart:html';

import 'package:signalr_core/signalr_core.dart';

void main() async {
  final connection = HubConnectionBuilder().withUrl('http://localhost:5000/chatHub', 
    HttpConnectionOptions(
      logging: (level, message) => print(message),
    )).withAutomaticReconnect().build();

  
  
  var button = querySelector('#sendButton');

  button.onClick.listen((e) {
    var user = (querySelector('#userInput') as InputElement).value;
    var message = (querySelector('#messageInput') as InputElement).value;

    connection.invoke('SendMessage', args: [user, message]);
  });
  
  connection.on('ReceiveMessage', (items) {
    var msg = items[1];
    var encodedMsg = items[0] + ' says ' + msg;
    var li = LIElement();
    li.text = encodedMsg;
    querySelector('#messagesList').append(li);
  });

  await connection.start();
}
