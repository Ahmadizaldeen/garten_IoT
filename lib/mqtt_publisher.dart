import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MqttConnectionSettings {
  const MqttConnectionSettings({
    required this.host,
    this.port = 1883,
    this.username = '',
    this.password = '',
  });

  final String host;
  final int port;
  final String username;
  final String password;

  String? get validationError {
    if (host.trim().isEmpty) return 'Broker-Adresse fehlt.';
    if (port < 1 || port > 65535) return 'Der MQTT-Port ist ungültig.';
    if (username.isEmpty != password.isEmpty) {
      return 'Benutzername und Passwort müssen gemeinsam gesetzt werden.';
    }
    return null;
  }
}

abstract interface class MqttSettingsStore {
  Future<MqttConnectionSettings?> load();
  Future<void> save(MqttConnectionSettings settings);
}

class SecureMqttSettingsStore implements MqttSettingsStore {
  static const String _hostKey = 'mqtt_broker_host';
  static const String _portKey = 'mqtt_broker_port';
  static const String _usernameKey = 'mqtt_broker_username';
  static const String _passwordKey = 'mqtt_broker_password';

  final SharedPreferencesAsync _preferences;
  final FlutterSecureStorage _secureStorage;

  SecureMqttSettingsStore({
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage? secureStorage,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  @override
  Future<MqttConnectionSettings?> load() async {
    final host = await _preferences.getString(_hostKey);
    if (host == null || host.trim().isEmpty) return null;

    final port = await _preferences.getInt(_portKey);
    final username = await _preferences.getString(_usernameKey);
    final password = await _secureStorage.read(key: _passwordKey);
    return MqttConnectionSettings(
      host: host,
      port: port ?? 1883,
      username: username ?? '',
      password: password ?? '',
    );
  }

  @override
  Future<void> save(MqttConnectionSettings settings) async {
    final validationError = settings.validationError;
    if (validationError != null) throw FormatException(validationError);

    await _preferences.setString(_hostKey, settings.host.trim());
    await _preferences.setInt(_portKey, settings.port);
    await _preferences.setString(_usernameKey, settings.username);
    await _secureStorage.write(
      key: _passwordKey,
      value: settings.password.isEmpty ? null : settings.password,
    );
  }
}

abstract interface class MqttPublisher {
  bool get isConnected;

  Future<void> connect(MqttConnectionSettings settings);
  Future<void> publishDhtReading({
    required double temperatureCelsius,
    required double humidityPercent,
  });
  Future<void> publishRelayState({required bool isOn});
  Future<void> disconnect();
}

String encodeDhtTelemetry({
  required double temperatureCelsius,
  required double humidityPercent,
}) {
  if (!temperatureCelsius.isFinite ||
      temperatureCelsius < 0 ||
      temperatureCelsius > 50 ||
      !humidityPercent.isFinite ||
      humidityPercent < 0 ||
      humidityPercent > 100) {
    throw ArgumentError(
      'DHT11-Messwerte liegen außerhalb des gültigen Bereichs.',
    );
  }

  return jsonEncode({
    'temperature_c': temperatureCelsius,
    'humidity_percent': humidityPercent,
  });
}

String encodeRelayStatus({required bool isOn}) {
  return jsonEncode({'relay_on': isOn});
}

class MqttClientPublisher implements MqttPublisher {
  static const String telemetryTopic = 'garten/pumpe/telemetry';
  static const String statusTopic = 'garten/pumpe/status';

  MqttServerClient? _client;

  @override
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Future<void> connect(MqttConnectionSettings settings) async {
    final validationError = settings.validationError;
    if (validationError != null) throw FormatException(validationError);

    await disconnect();

    final clientId = 'garten_android_${DateTime.now().microsecondsSinceEpoch}';
    final client = MqttServerClient(settings.host.trim(), clientId)
      ..port = settings.port
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..logging(on: false);
    _client = client;

    try {
      final status = await client.connect(
        settings.username.isEmpty ? null : settings.username,
        settings.password.isEmpty ? null : settings.password,
      );
      if (status?.state != MqttConnectionState.connected) {
        throw StateError(
          'Der Broker hat die Verbindung abgelehnt: '
          '${status?.returnCode ?? "keine Antwort"}.',
        );
      }
    } catch (error, stackTrace) {
      _client = null;
      client.autoReconnect = false;
      client.disconnect();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> publishDhtReading({
    required double temperatureCelsius,
    required double humidityPercent,
  }) async {
    _publishRetainedJson(
      telemetryTopic,
      encodeDhtTelemetry(
        temperatureCelsius: temperatureCelsius,
        humidityPercent: humidityPercent,
      ),
    );
  }

  @override
  Future<void> publishRelayState({required bool isOn}) async {
    _publishRetainedJson(statusTopic, encodeRelayStatus(isOn: isOn));
  }

  void _publishRetainedJson(String topic, String json) {
    final client = _client;
    if (client == null || !isConnected) {
      throw StateError('Keine MQTT-Verbindung zum Broker.');
    }

    final payload = MqttClientPayloadBuilder()..addUTF8String(json);
    final bytes = payload.payload;
    if (bytes == null) {
      throw StateError('MQTT-Payload konnte nicht erstellt werden.');
    }

    client.publishMessage(topic, MqttQos.atMostOnce, bytes, retain: true);
  }

  @override
  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    if (client == null) return;
    client.autoReconnect = false;
    client.disconnect();
  }
}
