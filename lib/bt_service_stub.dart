import 'bt_service.dart';
import 'pump_protocol.dart';

class UnsupportedBluetoothRelayService implements BluetoothRelayService {
  @override
  Stream<BluetoothRelayEvent> get events => const Stream.empty();

  @override
  bool get isConnected => false;

  @override
  String get platformInfo => 'Plattform nicht unterstützt';

  @override
  Future<void> connect(String address) async {
    throw UnsupportedError('Plattform wird nicht unterstützt.');
  }

  @override
  Future<void> sendCommand(RelayCommand command) async {
    throw UnsupportedError('Plattform wird nicht unterstützt.');
  }

  @override
  Future<void> disconnect() async {}
}

BluetoothRelayService createService() => UnsupportedBluetoothRelayService();
