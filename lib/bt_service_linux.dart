import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'bt_service.dart';
import 'device_address_store.dart';
import 'pump_protocol.dart';

class LinuxBluetoothRelayService implements BluetoothRelayService {
  static const MethodChannel _methodChannel = MethodChannel('garten/bluetooth');
  static const EventChannel _eventChannel = EventChannel(
    'garten/bluetooth/events',
  );

  final StreamController<BluetoothRelayEvent> _eventsController =
      StreamController<BluetoothRelayEvent>.broadcast();
  final PumpMessageDecoder _messageDecoder = PumpMessageDecoder();
  bool _isConnected = false;

  LinuxBluetoothRelayService() {
    _eventChannel.receiveBroadcastStream().listen(
      _handlePlatformEvent,
      onError: (Object error, StackTrace stackTrace) {
        _eventsController.addError(error, stackTrace);
      },
    );
  }

  @override
  Stream<BluetoothRelayEvent> get events => _eventsController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  String get platformInfo => 'Linux (Bluetooth Classic RFCOMM / SPP)';

  @override
  Future<void> connect(String address) async {
    final normalizedAddress = address.trim().toUpperCase();
    if (!isValidBluetoothAddress(normalizedAddress)) {
      throw const FormatException('Ungültige Bluetooth-MAC-Adresse.');
    }
    if (_isConnected) await disconnect();

    _messageDecoder.reset();
    await _methodChannel.invokeMethod<void>('connect', <String, Object>{
      'address': normalizedAddress,
    });
    _isConnected = true;
    try {
      await sendCommand(RelayCommand.requestState);
    } catch (error, stackTrace) {
      await disconnect();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> sendCommand(RelayCommand command) async {
    if (!_isConnected) {
      throw StateError('Keine Verbindung zum HC-06.');
    }
    final bytes = Uint8List.fromList(
      ascii.encode(PumpProtocol.encode(command)),
    );
    await _methodChannel.invokeMethod<void>('write', <String, Object>{
      'bytes': bytes,
    });
  }

  @override
  Future<void> disconnect() async {
    await _methodChannel.invokeMethod<void>('disconnect');
    _isConnected = false;
    _messageDecoder.reset();
  }

  void _handlePlatformEvent(dynamic event) {
    if (event is! Map<Object?, Object?>) {
      _eventsController.addError(
        const FormatException('Ungültiges Linux-Bluetooth-Ereignis.'),
      );
      return;
    }

    switch (event['type']) {
      case 'data':
        final bytes = event['bytes'];
        if (bytes is! List<int>) {
          _eventsController.addError(
            const FormatException('Ungültige Bluetooth-Nutzdaten.'),
          );
          return;
        }
        for (final message in _messageDecoder.addData(bytes)) {
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
      case 'disconnected':
        _isConnected = false;
        _messageDecoder.reset();
        _eventsController.add(const BluetoothConnectionLost());
      default:
        _eventsController.addError(
          FormatException(
            'Unbekannter Bluetooth-Ereignistyp: ${event['type']}',
          ),
        );
    }
  }
}

BluetoothRelayService createService() => LinuxBluetoothRelayService();
