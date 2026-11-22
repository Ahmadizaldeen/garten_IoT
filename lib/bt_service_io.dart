import 'dart:io';

import 'bt_service.dart';
import 'bt_service_android.dart';
import 'bt_service_linux.dart';

BluetoothRelayService createService() {
  if (Platform.isLinux) return LinuxBluetoothRelayService();
  return AndroidBluetoothRelayService();
}
