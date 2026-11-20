import 'package:shared_preferences/shared_preferences.dart';

abstract interface class DeviceAddressStore {
  Future<String?> load();
  Future<void> save(String address);
}

class SharedPreferencesDeviceAddressStore implements DeviceAddressStore {
  static const String _key = 'bluetooth_device_address';

  final SharedPreferencesAsync _preferences;

  SharedPreferencesDeviceAddressStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  @override
  Future<String?> load() => _preferences.getString(_key);

  @override
  Future<void> save(String address) {
    final normalizedAddress = address.trim().toUpperCase();
    if (!isValidBluetoothAddress(normalizedAddress)) {
      throw const FormatException('Ungültige Bluetooth-MAC-Adresse.');
    }
    return _preferences.setString(_key, normalizedAddress);
  }
}

bool isValidBluetoothAddress(String address) {
  return RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$').hasMatch(address);
}
