import 'package:signalr/signalr.dart';
import 'package:logging/logging.dart';

  

main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print(rec.message);
  });

  final Logger _logger = Logger('SignalR');

  var connection = HubConnection.withUrl(
    url: 'http://localhost:5000/chatHub', 
    options: HttpConnectionOptions(
      transport: HttpTransportType.longPolling, 
      logging: (level, message) {
        switch (level) {
          case LogLevel.trace:
            _logger.log(Level.FINEST, message);
            break;
          case LogLevel.debug:
            _logger.log(Level.FINE, message);
            break;
          case LogLevel.information:
            _logger.log(Level.INFO, message);
            break;
          case LogLevel.warning:
            _logger.log(Level.WARNING, message);
            break;
          case LogLevel.error:
            _logger.log(Level.SEVERE, message);
            break;
          case LogLevel.critical:
            _logger.log(Level.SHOUT, message);
            break;
          case LogLevel.none:
            _logger.log(Level.OFF, message);
            break;
    }
      },
      logMessageContent: false));
  
  await connection.start();

  connection.on('ReceiveMessage', (stuff) {
    print(stuff.toString());
  });

  await connection.invoke('SendMessage', args: ['duky', 'duke']);
}