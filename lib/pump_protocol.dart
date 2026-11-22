import 'dart:convert';

enum RelayCommand { turnOn, turnOff, requestState }

sealed class PumpMessage {
  const PumpMessage();
}

final class RelayStateMessage extends PumpMessage {
  const RelayStateMessage(this.isOn);

  final bool isOn;
}

final class DhtReadingMessage extends PumpMessage {
  const DhtReadingMessage(this.temperatureCelsius, this.humidityPercent);

  final double temperatureCelsius;
  final double humidityPercent;
}

final class DhtSensorErrorMessage extends PumpMessage {
  const DhtSensorErrorMessage();
}

abstract final class PumpProtocol {
  static const String statePrefix = 'STATE:';
  static const String dhtPrefix = 'DHT:';

  static String encode(RelayCommand command) {
    return switch (command) {
      RelayCommand.turnOn => '1',
      RelayCommand.turnOff => '0',
      RelayCommand.requestState => '?',
    };
  }

  static bool? parseState(String line) {
    final value = line.trim();
    if (value == '${statePrefix}1') return true;
    if (value == '${statePrefix}0') return false;
    return null;
  }

  // DHT lines carry Celsius and relative humidity; malformed or implausible
  // readings are ignored rather than shown as sensor data.
  static PumpMessage? parseMessage(String line) {
    final value = line.trim();
    if (value == '${statePrefix}1') return const RelayStateMessage(true);
    if (value == '${statePrefix}0') return const RelayStateMessage(false);

    if (!value.startsWith(dhtPrefix)) return null;
    final reading = value.substring(dhtPrefix.length);
    if (reading == 'ERR') return const DhtSensorErrorMessage();

    final separator = reading.indexOf(',');
    if (separator <= 0 || separator != reading.lastIndexOf(',')) return null;

    final temperature = double.tryParse(reading.substring(0, separator));
    final humidity = double.tryParse(reading.substring(separator + 1));
    if (temperature == null ||
        humidity == null ||
        !temperature.isFinite ||
        !humidity.isFinite ||
        temperature < 0 ||
        temperature > 50 ||
        humidity < 0 ||
        humidity > 100) {
      return null;
    }

    return DhtReadingMessage(temperature, humidity);
  }
}

class PumpMessageDecoder {
  String _buffer = '';

  // SPP may split a line across packets, so retain its unfinished tail.
  List<PumpMessage> addData(List<int> data) {
    _buffer += ascii.decode(data, allowInvalid: true);
    final messages = <PumpMessage>[];

    var newlineIndex = _buffer.indexOf('\n');
    while (newlineIndex >= 0) {
      final line = _buffer.substring(0, newlineIndex);
      _buffer = _buffer.substring(newlineIndex + 1);
      final message = PumpProtocol.parseMessage(line);
      if (message != null) messages.add(message);
      newlineIndex = _buffer.indexOf('\n');
    }

    if (_buffer.length > 128) _buffer = '';
    return messages;
  }

  void reset() {
    _buffer = '';
  }
}
