import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garten/bt_service.dart';
import 'package:garten/device_address_store.dart';
import 'package:garten/mqtt_publisher.dart';
import 'package:garten/relay_dashboard_screen.dart';
import 'package:garten/pump_protocol.dart';

void main() {
  late FakeBluetoothRelayService bluetoothService;
  late FakeDeviceAddressStore addressStore;
  late FakeMqttPublisher mqttPublisher;
  late FakeMqttSettingsStore mqttSettingsStore;

  setUp(() {
    bluetoothService = FakeBluetoothRelayService();
    addressStore = FakeDeviceAddressStore();
    mqttPublisher = FakeMqttPublisher();
    mqttSettingsStore = FakeMqttSettingsStore();
  });

  tearDown(() async {
    await bluetoothService.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RelayDashboardScreen(
          bluetoothService: bluetoothService,
          addressStore: addressStore,
          mqttPublisher: mqttPublisher,
          mqttSettingsStore: mqttSettingsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> configureAddress(WidgetTester tester, String address) async {
    await tester.tap(find.byTooltip('Bluetooth-Gerät einstellen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('device-address-input')),
      address,
    );
    await tester.tap(find.byKey(const Key('save-device-address')));
    await tester.pumpAndSettle();
  }

  testWidgets('requires a valid device address before connecting', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('ZUSTAND UNBEKANNT'), findsOneWidget);
    expect(find.textContaining('nicht konfiguriert'), findsOneWidget);
    expect(find.text('Verbinden'), findsOneWidget);
    expect(_connectionButton(tester).onPressed, isNull);

    await tester.tap(find.byTooltip('Bluetooth-Gerät einstellen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('device-address-input')),
      'not-a-mac-address',
    );
    await tester.tap(find.byKey(const Key('save-device-address')));
    await tester.pumpAndSettle();

    expect(find.text('Gib eine gültige MAC-Adresse ein.'), findsOneWidget);
    expect(addressStore.savedAddress, isNull);
    expect(bluetoothService.connectedAddress, isNull);
  });

  testWidgets('saves the address and connects to the configured device', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await configureAddress(tester, '98:d3:51:f9:41:b1');

    expect(addressStore.savedAddress, '98:D3:51:F9:41:B1');
    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();

    expect(bluetoothService.connectedAddress, '98:D3:51:F9:41:B1');
    expect(find.text('Verbindung: Verbunden'), findsOneWidget);
    expect(find.text('PUMPE AUS (0)'), findsOneWidget);
    expect(bluetoothService.sentCommands, [RelayCommand.requestState]);
  });

  testWidgets('shows Arduino-confirmed state after sending pump commands', (
    WidgetTester tester,
  ) async {
    addressStore.savedAddress = '98:D3:51:F9:41:B1';
    await pumpApp(tester);

    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EIN (1)'));
    await tester.pumpAndSettle();

    expect(bluetoothService.sentCommands, [
      RelayCommand.requestState,
      RelayCommand.turnOn,
    ]);
    expect(find.text('PUMPE LÄUFT (1)'), findsOneWidget);
    expect(
      find.textContaining('Arduino bestätigt: Pumpe EIN.'),
      findsOneWidget,
    );

    await tester.tap(find.text('AUS (0)'));
    await tester.pumpAndSettle();

    expect(bluetoothService.sentCommands.last, RelayCommand.turnOff);
    expect(find.text('PUMPE AUS (0)'), findsOneWidget);
  });

  testWidgets('displays DHT11 readings and sensor errors', (
    WidgetTester tester,
  ) async {
    addressStore.savedAddress = '98:D3:51:F9:41:B1';
    await pumpApp(tester);

    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    expect(find.text('Warte auf Messwerte'), findsOneWidget);

    bluetoothService.updateDhtReading(23.5, 56);
    await tester.pumpAndSettle();

    expect(find.text('Temperatur: 23.5 °C'), findsOneWidget);
    expect(find.text('Luftfeuchtigkeit: 56.0 %'), findsOneWidget);
    expect(find.text('Aktuelle Messwerte'), findsOneWidget);

    bluetoothService.reportDhtError();
    await tester.pumpAndSettle();
    expect(find.text('Sensorfehler (DHT11)'), findsOneWidget);
  });

  testWidgets('publishes DHT readings to the configured MQTT broker', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('MQTT einstellen'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mqtt-host-input')),
      '192.168.1.20',
    );
    await tester.enterText(
      find.byKey(const Key('mqtt-username-input')),
      'garten_app',
    );
    await tester.enterText(
      find.byKey(const Key('mqtt-password-input')),
      'test-password',
    );
    await tester.tap(find.byKey(const Key('save-mqtt-settings')));
    await tester.pumpAndSettle();

    expect(mqttSettingsStore.savedSettings?.host, '192.168.1.20');
    expect(mqttSettingsStore.savedSettings?.port, 1883);
    expect(mqttPublisher.connectedSettings?.username, 'garten_app');
    expect(mqttPublisher.isConnected, isTrue);

    bluetoothService.updateDhtReading(23.5, 56);
    await tester.pumpAndSettle();

    expect(mqttPublisher.publishedReadings, [
      {'temperatureCelsius': 23.5, 'humidityPercent': 56.0},
    ]);
  });

  testWidgets('publishes Arduino-confirmed relay status to MQTT', (
    WidgetTester tester,
  ) async {
    addressStore.savedAddress = '98:D3:51:F9:41:B1';
    bluetoothService.autoRespondToCommands = false;
    mqttSettingsStore.savedSettings = const MqttConnectionSettings(
      host: '192.168.1.20',
    );
    await pumpApp(tester);

    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    expect(mqttPublisher.publishedRelayStates, [false]);

    await tester.tap(find.text('EIN (1)'));
    await tester.pumpAndSettle();
    expect(mqttPublisher.publishedRelayStates, [false]);

    bluetoothService.confirmState(true);
    await tester.pumpAndSettle();

    expect(mqttPublisher.publishedRelayStates, [false, true]);
  });

  testWidgets(
    'does not assume a command changed the relay before confirmation',
    (WidgetTester tester) async {
      addressStore.savedAddress = '98:D3:51:F9:41:B1';
      bluetoothService.autoRespondToCommands = false;
      await pumpApp(tester);

      await tester.tap(find.text('Verbinden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EIN (1)'));
      await tester.pumpAndSettle();

      expect(find.text('PUMPE AUS (0)'), findsOneWidget);

      bluetoothService.confirmState(true);
      await tester.pumpAndSettle();
      expect(find.text('PUMPE LÄUFT (1)'), findsOneWidget);
    },
  );

  testWidgets('keeps the confirmed state and logs a send failure', (
    WidgetTester tester,
  ) async {
    addressStore.savedAddress = '98:D3:51:F9:41:B1';
    bluetoothService.sendError = StateError('Senden fehlgeschlagen');
    await pumpApp(tester);

    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EIN (1)'));
    await tester.pumpAndSettle();

    expect(find.text('PUMPE AUS (0)'), findsOneWidget);
    expect(
      find.textContaining('Sendefehler: Bad state: Senden fehlgeschlagen'),
      findsOneWidget,
    );
  });

  testWidgets('connection errors leave the controls disabled', (
    WidgetTester tester,
  ) async {
    addressStore.savedAddress = '98:D3:51:F9:41:B1';
    bluetoothService.connectError = StateError('Verbindung fehlgeschlagen');
    await pumpApp(tester);

    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();

    expect(find.text('Verbindung: Nicht verbunden'), findsOneWidget);
    expect(find.textContaining('Verbindung fehlgeschlagen'), findsOneWidget);
    expect(_pumpButton(tester, 'EIN (1)').onPressed, isNull);
    expect(_pumpButton(tester, 'AUS (0)').onPressed, isNull);
  });

  testWidgets('disconnect clears the displayed state until the next report', (
    WidgetTester tester,
  ) async {
    addressStore.savedAddress = '98:D3:51:F9:41:B1';
    await pumpApp(tester);
    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    bluetoothService.updateDhtReading(23.5, 56);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EIN (1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trennen'));
    await tester.pumpAndSettle();

    expect(bluetoothService.disconnectCount, 1);
    expect(find.text('Verbindung: Nicht verbunden'), findsOneWidget);
    expect(find.text('ZUSTAND UNBEKANNT'), findsOneWidget);
    expect(find.text('Temperatur: -- °C'), findsOneWidget);
    expect(find.text('Luftfeuchtigkeit: -- %'), findsOneWidget);
    expect(find.text('Nicht verbunden'), findsOneWidget);
    expect(_pumpButton(tester, 'EIN (1)').onPressed, isNull);
  });

  testWidgets('remote disconnect clears the connection and pump state', (
    WidgetTester tester,
  ) async {
    addressStore.savedAddress = '98:D3:51:F9:41:B1';
    await pumpApp(tester);
    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EIN (1)'));
    await tester.pumpAndSettle();

    bluetoothService.loseConnection();
    await tester.pumpAndSettle();

    expect(find.text('Verbindung: Nicht verbunden'), findsOneWidget);
    expect(find.text('ZUSTAND UNBEKANNT'), findsOneWidget);
    expect(_pumpButton(tester, 'EIN (1)').onPressed, isNull);
  });
}

FilledButton _connectionButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Verbinden'),
      matching: find.byType(FilledButton),
    ),
  );
}

ElevatedButton _pumpButton(WidgetTester tester, String label) {
  return tester.widget<ElevatedButton>(
    find.ancestor(of: find.text(label), matching: find.byType(ElevatedButton)),
  );
}

class FakeDeviceAddressStore implements DeviceAddressStore {
  String? savedAddress;

  @override
  Future<String?> load() async => savedAddress;

  @override
  Future<void> save(String address) async {
    savedAddress = address;
  }
}

class FakeMqttSettingsStore implements MqttSettingsStore {
  MqttConnectionSettings? savedSettings;

  @override
  Future<MqttConnectionSettings?> load() async => savedSettings;

  @override
  Future<void> save(MqttConnectionSettings settings) async {
    savedSettings = settings;
  }
}

class FakeMqttPublisher implements MqttPublisher {
  bool _isConnected = false;
  MqttConnectionSettings? connectedSettings;
  final List<Map<String, double>> publishedReadings = [];
  final List<bool> publishedRelayStates = [];

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect(MqttConnectionSettings settings) async {
    connectedSettings = settings;
    _isConnected = true;
  }

  @override
  Future<void> publishDhtReading({
    required double temperatureCelsius,
    required double humidityPercent,
  }) async {
    if (!_isConnected) throw StateError('MQTT is not connected.');
    publishedReadings.add({
      'temperatureCelsius': temperatureCelsius,
      'humidityPercent': humidityPercent,
    });
  }

  @override
  Future<void> publishRelayState({required bool isOn}) async {
    if (!_isConnected) throw StateError('MQTT is not connected.');
    publishedRelayStates.add(isOn);
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
  }
}

class FakeBluetoothRelayService implements BluetoothRelayService {
  final StreamController<BluetoothRelayEvent> _events =
      StreamController<BluetoothRelayEvent>.broadcast(sync: true);
  final List<RelayCommand> sentCommands = [];

  Object? connectError;
  Object? sendError;
  bool autoRespondToCommands = true;
  String? connectedAddress;
  int disconnectCount = 0;
  bool _isConnected = false;
  bool _pumpIsOn = false;

  @override
  Stream<BluetoothRelayEvent> get events => _events.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  String get platformInfo => 'Test Bluetooth';

  @override
  Future<void> connect(String address) async {
    if (connectError case final error?) throw error;
    connectedAddress = address;
    _isConnected = true;
    _events.add(RelayStateChanged(_pumpIsOn));
    sentCommands.add(RelayCommand.requestState);
  }

  @override
  Future<void> sendCommand(RelayCommand command) async {
    sentCommands.add(command);
    if (sendError case final error?) throw error;
    if (!autoRespondToCommands) return;

    switch (command) {
      case RelayCommand.turnOn:
        _pumpIsOn = true;
        _events.add(RelayStateChanged(_pumpIsOn));
      case RelayCommand.turnOff:
        _pumpIsOn = false;
        _events.add(RelayStateChanged(_pumpIsOn));
      case RelayCommand.requestState:
        _events.add(RelayStateChanged(_pumpIsOn));
    }
  }

  void confirmState(bool isOn) {
    _pumpIsOn = isOn;
    _events.add(RelayStateChanged(isOn));
  }

  void updateDhtReading(double temperatureCelsius, double humidityPercent) {
    _events.add(DhtReadingUpdated(temperatureCelsius, humidityPercent));
  }

  void reportDhtError() {
    _events.add(const DhtReadingUnavailable());
  }

  void loseConnection() {
    _isConnected = false;
    _events.add(const BluetoothConnectionLost());
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    _isConnected = false;
  }

  Future<void> dispose() => _events.close();
}
