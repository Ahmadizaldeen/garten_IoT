import 'dart:convert';

enum RelayCommand { turnOn, turnOff, requestState }

abstract final class PumpProtocol {
  static const String statePrefix = 'STATE:';

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
}

class PumpStateDecoder {
  String _buffer = '';

  List<bool> addData(List<int> data) {
    _buffer += ascii.decode(data, allowInvalid: true);
    final states = <bool>[];

    var newlineIndex = _buffer.indexOf('\n');
    while (newlineIndex >= 0) {
      final line = _buffer.substring(0, newlineIndex);
      _buffer = _buffer.substring(newlineIndex + 1);
      final state = PumpProtocol.parseState(line);
      if (state != null) states.add(state);
      newlineIndex = _buffer.indexOf('\n');
    }

    if (_buffer.length > 128) _buffer = '';
    return states;
  }

  void reset() {
    _buffer = '';
  }
}
