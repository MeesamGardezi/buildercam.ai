import 'package:buildercam/core/core.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SowSocketSyncService {
  io.Socket? _socket;
  bool _connected = false;

  void connect(String projectId) {
    _socket = io.io(
      ApiConfig.sowProxyBaseUrl,
      io.OptionBuilder()
          .setTransports(<String>['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      _connected = true;
      _socket!.emit('join_project', <String, dynamic>{'projectId': projectId});
    });

    _socket!.onDisconnect((_) {
      _connected = false;
    });

    _socket!.on('transcript_error', (_) {
      // Intentionally no-throw: REST persistence remains source of truth.
    });

    _socket!.connect();
  }

  void emitUpdate({
    required String projectId,
    required String rawTranscript,
    required int durationSeconds,
    String? transcriptId,
    String createdBy = 'flutter-client',
  }) {
    if (!_connected || _socket == null) {
      return;
    }

    _socket!.emit('transcript_update', <String, dynamic>{
      'projectId': projectId,
      'transcriptId': transcriptId,
      'rawTranscript': rawTranscript,
      'durationSeconds': durationSeconds,
      'createdBy': createdBy,
    });
  }

  void emitFinal({
    required String projectId,
    required String rawTranscript,
    required int durationSeconds,
    String? transcriptId,
    String createdBy = 'flutter-client',
  }) {
    if (!_connected || _socket == null) {
      return;
    }

    _socket!.emit('transcript_final', <String, dynamic>{
      'projectId': projectId,
      'transcriptId': transcriptId,
      'rawTranscript': rawTranscript,
      'durationSeconds': durationSeconds,
      'createdBy': createdBy,
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }
}
