import 'package:http/http.dart';
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
      transport: HttpTransportType.serverSentEvents, 
      //client: CustomClient(Client()),
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

class CustomClient extends BaseClient {

  BaseClient _inner;

  CustomClient(this._inner);

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    RequestStart(request);

    var duration = Stopwatch()
      ..start();

    return _inner.send(request).then((response) async {
      
      duration.stop();

      RequestEnd(response, duration);

      return response;
    });
  }

  void RequestEnd(BaseResponse response, Stopwatch duration) {
    var sb = StringBuffer();
    sb.write('Received HTTP response after ${duration.elapsedMilliseconds}ms - ${response.statusCode}');

    sb.writeln('Response Headers:');

    sb.writeln('status: ${response.statusCode}');

    response.headers.forEach((key, value) {
      sb.write(key);
      sb.write(': ');
      sb.write(value);
      sb.writeln();
    });

    sb.writeln('content-length: ${response.contentLength}');

    print(sb.toString());
  }
  
  
  void RequestStart(BaseRequest request) {
    var sb = StringBuffer();
    sb.write('Sending HTTP request ${request.method} ${request.url.toString()}');

    sb.writeln('Request Headers:');

    request.headers.forEach((key, value) {
      sb.write(key);
      sb.write(': ');
      sb.write(value);
      sb.writeln();
    });
    
    print(sb.toString());
  }
}