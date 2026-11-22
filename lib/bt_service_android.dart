import 'dart:async';
import 'dart:convert';

import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bt_service.dart';
import 'pump_protocol.dart';

class AndroidBluetoothRelayService implements BluetoothRelayService {
  BluetoothConnection? _connection;
  StreamSubscription<List<int>>? _inputSubscription;
  final StreamController<BluetoothRelayEvent> _eventsController =
      StreamController<BluetoothRelayEvent>.broadcast();
  final PumpMessageDecoder _messageDecoder = PumpMessageDecoder();

  @override
  Stream<BluetoothRelayEvent> get events => _eventsController.stream;

  @override
  bool get isConnected => _connection?.isConnected ?? false;

  @override
  String get platformInfo => 'Android (Bluetooth Classic SPP)';

  @override
  Future<void> connect(String address) async {
    final permission = await Permission.bluetoothConnect.request();
    if (!permission.isGranted) {
      throw StateError(
        'Die Bluetooth-Verbindungsberechtigung wurde nicht erteilt.',
      );
    }

    if (_connection != null) await disconnect();

    _connection = await BluetoothConnection.toAddress(address);
    _messageDecoder.reset();
    _inputSubscription = _connection!.input.listen(
      _handleIncomingData,
      onError: (Object error, StackTrace stackTrace) {
        _eventsController.addError(error, stackTrace);
      },
      onDone: _handleConnectionLost,
    );
    try {
      await sendCommand(RelayCommand.requestState);
    } catch (error, stackTrace) {
      await disconnect();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> sendCommand(RelayCommand command) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) {
      throw StateError('Keine Verbindung zum HC-06.');
    }
    final bytes = ascii.encode(PumpProtocol.encode(command));
    connection.output.add(bytes);
    await connection.output.allSent;
  }

  @override
  Future<void> disconnect() async {
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    final connection = _connection;
    _connection = null;
    _messageDecoder.reset();
    await connection?.close();
  }

  void _handleIncomingData(List<int> data) {
    // Keep telemetry separate from relay state when translating wire messages.
    for (final message in _messageDecoder.addData(data)) {
      switch (message) {
        case RelayStateMessage(:final isOn):
          _eventsController.add(RelayStateChanged(isOn));
        case DhtReadingMessage(
          :final temperatureCelsius,
          :final humidityPercent,
        ):
          _eventsController.add(
            DhtReadingUpdated(temperatureCelsius, humidityPercent),
          );
        case DhtSensorErrorMessage():
          _eventsController.add(const DhtReadingUnavailable());
      }
    }
  }

  void _handleConnectionLost() {
    _connection = null;
    _inputSubscription = null;
    _messageDecoder.reset();
    _eventsController.add(const BluetoothConnectionLost());
  }
}

BluetoothRelayService createService() => AndroidBluetoothRelayService();
