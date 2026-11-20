import 'bt_service_stub.dart'
    if (dart.library.io) 'bt_service_android.dart'
    if (dart.library.html) 'bt_service_web.dart';

import 'pump_protocol.dart';

sealed class BluetoothRelayEvent {
  const BluetoothRelayEvent();
}

final class RelayStateChanged extends BluetoothRelayEvent {
  const RelayStateChanged(this.isOn);

  final bool isOn;
}

final class DhtReadingUpdated extends BluetoothRelayEvent {
  const DhtReadingUpdated(this.temperatureCelsius, this.humidityPercent);

  final double temperatureCelsius;
  final double humidityPercent;
}

final class DhtReadingUnavailable extends BluetoothRelayEvent {
  const DhtReadingUnavailable();
}

final class BluetoothConnectionLost extends BluetoothRelayEvent {
  const BluetoothConnectionLost();
}

abstract class BluetoothRelayService {
  Stream<BluetoothRelayEvent> get events;

  Future<void> connect(String address);
  Future<void> sendCommand(RelayCommand command);
  Future<void> disconnect();
  bool get isConnected;
  String get platformInfo;
}

BluetoothRelayService getBluetoothService() => createService();
