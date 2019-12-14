# ASP.NET Core SignalR Dart client

## Introduction

ASP.NET Core **SignalR** is an open-source library that simplifies adding real-time web functionality to apps. Real-time web functionality enables server-side code to push content to clients instantly.

## Example
```dart 
final connection = HubConnectionBuilder().withUrl('http://localhost:5000/chatHub', 
    HttpConnectionOptions(
        logging: (level, message) => print(message),
    )).build();
 
await connection.start();

connection.on('ReceiveMessage', (stuff) {
    print(stuff.toString());
});

await connection.invoke('SendMessage', args: ['Bob', 'Says hi!']);
```
