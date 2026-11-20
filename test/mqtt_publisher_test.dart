import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garten/mqtt_publisher.dart';

void main() {
  test('encodes DHT readings as MQTT JSON telemetry', () {
    expect(MqttClientPublisher.telemetryTopic, 'garten/pumpe/telemetry');
    expect(
      encodeDhtTelemetry(temperatureCelsius: 23, humidityPercent: 56),
      jsonEncode({'temperature_c': 23.0, 'humidity_percent': 56.0}),
    );
  });

  test('rejects invalid DHT readings before publishing', () {
    expect(
      () => encodeDhtTelemetry(
        temperatureCelsius: double.nan,
        humidityPercent: 56,
      ),
      throwsArgumentError,
    );
    expect(
      () => encodeDhtTelemetry(temperatureCelsius: 23, humidityPercent: 101),
      throwsArgumentError,
    );
  });

  test('encodes the confirmed relay status on its own MQTT topic', () {
    expect(MqttClientPublisher.statusTopic, 'garten/pumpe/status');
    expect(encodeRelayStatus(isOn: true), jsonEncode({'relay_on': true}));
    expect(encodeRelayStatus(isOn: false), jsonEncode({'relay_on': false}));
  });
}
