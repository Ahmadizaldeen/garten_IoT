import 'bt_service.dart';
import 'pump_protocol.dart';

class WebBluetoothRelayService implements BluetoothRelayService {
  @override
  Stream<BluetoothRelayEvent> get events => const Stream.empty();

  @override
  bool get isConnected => false;

  @override
  String get platformInfo => 'Web (Classic BT / HC-06 nicht verfügbar)';

  @override
  Future<void> connect(String address) async {
    throw UnsupportedError(
      'Web-Browser unterstützen kein Bluetooth Classic (HC-06). '
      'Bitte nutze die Android-App oder wechsle auf ein BLE-Modul (z.B. HM-10 / ESP32).',
    );
  }

  @override
  Future<void> sendCommand(RelayCommand command) async {
    throw UnsupportedError('Senden im Web nicht möglich.');
  }

  @override
  Future<void> disconnect() async {}
}

BluetoothRelayService createService() => WebBluetoothRelayService();
