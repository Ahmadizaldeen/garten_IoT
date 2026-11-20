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

  test('decodes state messages split across serial packets', () {
    final decoder = PumpStateDecoder();

    expect(decoder.addData(ascii.encode('STA')), isEmpty);
    expect(decoder.addData(ascii.encode('TE:1\r\nSTATE:0\nUNKNOWN\n')), [
      true,
      false,
    ]);
  });
}
