## Introduction

ASP.NET Core **SignalR** is an open-source library that simplifies adding real-time web functionality to apps. Real-time web functionality enables server-side code to push content to clients instantly. It's platform-independent, and can be used on both the command-line and the browser.

## Example
```dart 
final connection = HubConnectionBuilder().withUrl('http://localhost:5000/chatHub', 
    HttpConnectionOptions(
        logging: (level, message) => print(message),
    )).build();
 
await connection.start();

connection.on('ReceiveMessage', (message) {
    print(message.toString());
});

await connection.invoke('SendMessage', args: ['Bob', 'Says hi!']);
```
