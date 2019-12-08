import 'package:signalr/src/transport.dart' as transfer;
import 'package:signalr/src/utils.dart';

abstract class Connection {
  Connection({
    this.features,
    this.connectionId
  });
  
  final dynamic features;

  final String connectionId;

  String baseUrl;

  OnReceive onReceive;

  OnClose onClose;

  Future<void> start({transfer.TransferFormat transferFormat = transfer.TransferFormat.binary});

  Future<void> send(dynamic data);

  Future<void> stop({Exception exception});
}