import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:garten/pump_protocol.dart';

void main() {
  test('encodes the pump commands and state query', () {
    expect(PumpProtocol.encode(RelayCommand.turnOn), '1');
    expect(PumpProtocol.encode(RelayCommand.turnOff), '0');
    expect(PumpProtocol.encode(RelayCommand.requestState), '?');
  });

  test('parses Arduino state lines with serial line endings', () {
    expect(PumpProtocol.parseState('STATE:1\r'), isTrue);
    expect(PumpProtocol.parseState('STATE:0\r'), isFalse);
    expect(PumpProtocol.parseState('UNKNOWN\r'), isNull);
    expect(PumpProtocol.parseState('STATE:2\r'), isNull);
  });

  test('parses DHT readings and sensor errors', () {
    expect(
      PumpProtocol.parseMessage('DHT:23.5,56.0\r'),
      isA<DhtReadingMessage>()
          .having((message) => message.temperatureCelsius, 'temperature', 23.5)
          .having((message) => message.humidityPercent, 'humidity', 56.0),
    );
    expect(PumpProtocol.parseMessage('DHT:ERR'), isA<DhtSensorErrorMessage>());
  });

  test('ignores malformed or out-of-range DHT readings', () {
    expect(PumpProtocol.parseMessage('DHT:NaN,56'), isNull);
    expect(PumpProtocol.parseMessage('DHT:51,56'), isNull);
    expect(PumpProtocol.parseMessage('DHT:23,101'), isNull);
    expect(PumpProtocol.parseMessage('DHT:23'), isNull);
  });

  test('decodes mixed messages split across serial packets', () {
    final decoder = PumpMessageDecoder();

    expect(decoder.addData(ascii.encode('STA')), isEmpty);
    final relayMessages = decoder.addData(
      ascii.encode('TE:1\r\nSTATE:0\nUNKNOWN\n'),
    );
    expect(relayMessages, hasLength(2));
    expect(
      relayMessages[0],
      isA<RelayStateMessage>().having((message) => message.isOn, 'isOn', true),
    );
    expect(
      relayMessages[1],
      isA<RelayStateMessage>().having((message) => message.isOn, 'isOn', false),
    );

    expect(decoder.addData(ascii.encode('DHT:23.5,')), isEmpty);
    final sensorMessages = decoder.addData(ascii.encode('56.0\nDHT:ERR\n'));
    expect(sensorMessages, hasLength(2));
    expect(
      sensorMessages[0],
      isA<DhtReadingMessage>()
          .having((message) => message.temperatureCelsius, 'temperature', 23.5)
          .having((message) => message.humidityPercent, 'humidity', 56.0),
    );
    expect(sensorMessages[1], isA<DhtSensorErrorMessage>());
  });
}
