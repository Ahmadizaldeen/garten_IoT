import 'dart:async';

import 'package:flutter/material.dart';

import 'bt_service.dart';
import 'device_address_store.dart';
import 'mqtt_publisher.dart';
import 'pump_protocol.dart';

class RelayScreenConfig {
  static const String deviceName = 'HC-06';
  static const double logFontSize = 14;
  static const bool showSend = true;
  static const bool showStatus = true;
  static const bool showTimestamp = true;
  static const bool autoScroll = true;
}

class RelayDashboardScreen extends StatefulWidget {
  const RelayDashboardScreen({
    super.key,
    this.bluetoothService,
    this.addressStore,
    this.mqttPublisher,
    this.mqttSettingsStore,
  });

  final BluetoothRelayService? bluetoothService;
  final DeviceAddressStore? addressStore;
  final MqttPublisher? mqttPublisher;
  final MqttSettingsStore? mqttSettingsStore;

  @override
  State<RelayDashboardScreen> createState() => _RelayDashboardScreenState();
}

class _RelayDashboardScreenState extends State<RelayDashboardScreen> {
  late final BluetoothRelayService _bluetoothService;
  late final DeviceAddressStore _addressStore;
  late final MqttPublisher _mqttPublisher;
  late final MqttSettingsStore _mqttSettingsStore;
  final ScrollController _scrollController = ScrollController();
  final List<String> _logs = [];
  StreamSubscription<BluetoothRelayEvent>? _eventSubscription;

  String _deviceAddress = '';
  bool _isLoadingAddress = true;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool? _isRelayOn;
  double? _temperatureCelsius;
  double? _humidityPercent;
  bool _dhtSensorError = false;
  MqttConnectionSettings? _mqttSettings;
  bool _isMqttConnected = false;
  bool _isMqttConnecting = false;
  bool _mqttPublishErrorLogged = false;
  bool? _lastPublishedRelayState;

  @override
  void initState() {
    super.initState();
    _bluetoothService = widget.bluetoothService ?? getBluetoothService();
    _addressStore =
        widget.addressStore ?? SharedPreferencesDeviceAddressStore();
    _mqttPublisher = widget.mqttPublisher ?? MqttClientPublisher();
    _mqttSettingsStore = widget.mqttSettingsStore ?? SecureMqttSettingsStore();
    _eventSubscription = _bluetoothService.events.listen(
      _handleBluetoothEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (mounted) {
          _addLog('Bluetooth-Empfangsfehler: $error', isStatus: true);
        }
      },
    );
    _loadDeviceAddress();
    _loadMqttSettings();
  }

  Future<void> _loadDeviceAddress() async {
    try {
      final savedAddress = await _addressStore.load();
      if (!mounted) return;
      setState(() {
        _deviceAddress = savedAddress?.trim().toUpperCase() ?? '';
        _isLoadingAddress = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingAddress = false);
      _addLog(
        'Gespeicherte Bluetooth-Adresse konnte nicht geladen werden: $error',
        isStatus: true,
      );
    }
  }

  Future<void> _loadMqttSettings() async {
    try {
      final settings = await _mqttSettingsStore.load();
      if (settings != null && mounted) {
        setState(() => _mqttSettings = settings);
        await _connectMqtt(settings);
      }
    } catch (error) {
      if (mounted) {
        _addLog(
          'MQTT-Einstellungen konnten nicht geladen werden: $error',
          isStatus: true,
        );
      }
    }
  }

  void _handleBluetoothEvent(BluetoothRelayEvent event) {
    if (!mounted) return;
    // Sensor events update only their own display state, never the relay state.
    switch (event) {
      case RelayStateChanged(:final isOn):
        setState(() => _isRelayOn = isOn);
        _addLog(
          'Arduino bestätigt: Pumpe ${isOn ? "EIN" : "AUS"}.',
          isStatus: true,
        );
        // Publish the Arduino-confirmed state, not just the requested command.
        unawaited(_publishRelayState(isOn: isOn));
      case DhtReadingUpdated(:final temperatureCelsius, :final humidityPercent):
        setState(() {
          _temperatureCelsius = temperatureCelsius;
          _humidityPercent = humidityPercent;
          _dhtSensorError = false;
          _isMqttConnected = _mqttPublisher.isConnected;
        });
        unawaited(
          _publishDhtReading(
            temperatureCelsius: temperatureCelsius,
            humidityPercent: humidityPercent,
          ),
        );
        final relayIsOn = _isRelayOn;
        if (relayIsOn != null) {
          unawaited(_publishRelayState(isOn: relayIsOn));
        }
      case DhtReadingUnavailable():
        setState(() => _dhtSensorError = true);
      case BluetoothConnectionLost():
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _isRelayOn = null;
          _temperatureCelsius = null;
          _humidityPercent = null;
          _dhtSensorError = false;
        });
        _addLog('Bluetooth-Verbindung wurde unterbrochen.', isStatus: true);
    }
  }

  String _formatTimestamp() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    final seconds = now.second.toString().padLeft(2, '0');
    final milliseconds = now.millisecond.toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds.$milliseconds';
  }

  void _addLog(String message, {bool isStatus = false, bool isSend = false}) {
    if ((isStatus && !RelayScreenConfig.showStatus) ||
        (isSend && !RelayScreenConfig.showSend)) {
      return;
    }

    final timestamp = RelayScreenConfig.showTimestamp
        ? '[${_formatTimestamp()}] '
        : '';
    setState(() {
      _logs.add('$timestamp$message');
      if (_logs.length > 500) _logs.removeRange(0, _logs.length - 500);
    });

    if (RelayScreenConfig.autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _editDeviceAddress() async {
    try {
      final address = await showDialog<String>(
        context: context,
        builder: (_) => _DeviceAddressDialog(initialAddress: _deviceAddress),
      );

      if (address == null) return;
      await _addressStore.save(address);
      if (!mounted) return;
      setState(() => _deviceAddress = address);
      _addLog('Bluetooth-Adresse gespeichert.', isStatus: true);
    } catch (error) {
      if (mounted) {
        _addLog(
          'Bluetooth-Adresse konnte nicht gespeichert werden: $error',
          isStatus: true,
        );
      }
    }
  }

  Future<void> _editMqttSettings() async {
    final settings = await showDialog<MqttConnectionSettings>(
      context: context,
      builder: (_) => _MqttSettingsDialog(initialSettings: _mqttSettings),
    );
    if (settings == null) return;

    try {
      await _mqttSettingsStore.save(settings);
      if (mounted) {
        setState(() => _mqttSettings = settings);
        await _connectMqtt(settings);
      }
    } catch (error) {
      if (mounted) {
        _addLog(
          'MQTT-Einstellungen konnten nicht gespeichert werden: $error',
          isStatus: true,
        );
      }
    }
  }

  Future<void> _connectMqtt(MqttConnectionSettings settings) async {
    if (_isMqttConnecting) return;
    setState(() {
      _isMqttConnecting = true;
      _isMqttConnected = false;
    });
    _lastPublishedRelayState = null;

    try {
      await _mqttPublisher.connect(settings);
      if (!mounted) return;
      setState(() => _isMqttConnected = _mqttPublisher.isConnected);
      _mqttPublishErrorLogged = false;
      _addLog(
        'Mit MQTT-Broker ${settings.host}:${settings.port} verbunden.',
        isStatus: true,
      );
      final relayIsOn = _isRelayOn;
      if (relayIsOn != null) {
        unawaited(_publishRelayState(isOn: relayIsOn));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isMqttConnected = false);
        _addLog('MQTT-Verbindung fehlgeschlagen: $error', isStatus: true);
      }
    } finally {
      if (mounted) setState(() => _isMqttConnecting = false);
    }
  }

  Future<void> _publishDhtReading({
    required double temperatureCelsius,
    required double humidityPercent,
  }) async {
    if (!_mqttPublisher.isConnected) {
      _lastPublishedRelayState = null;
      if (mounted && _isMqttConnected) {
        setState(() => _isMqttConnected = false);
      }
      return;
    }

    try {
      await _mqttPublisher.publishDhtReading(
        temperatureCelsius: temperatureCelsius,
        humidityPercent: humidityPercent,
      );
      _mqttPublishErrorLogged = false;
    } catch (error) {
      if (!mounted) return;
      setState(() => _isMqttConnected = _mqttPublisher.isConnected);
      if (!_mqttPublishErrorLogged) {
        _addLog('MQTT-Publish fehlgeschlagen: $error', isStatus: true);
        _mqttPublishErrorLogged = true;
      }
    }
  }

  Future<void> _publishRelayState({required bool isOn}) async {
    if (!_mqttPublisher.isConnected) {
      _lastPublishedRelayState = null;
      if (mounted && _isMqttConnected) {
        setState(() => _isMqttConnected = false);
      }
      return;
    }
    if (_lastPublishedRelayState == isOn) return;

    try {
      await _mqttPublisher.publishRelayState(isOn: isOn);
      _lastPublishedRelayState = isOn;
      _mqttPublishErrorLogged = false;
    } catch (error) {
      if (!mounted) return;
      setState(() => _isMqttConnected = _mqttPublisher.isConnected);
      if (!_mqttPublishErrorLogged) {
        _addLog('MQTT-Status-Publish fehlgeschlagen: $error', isStatus: true);
        _mqttPublishErrorLogged = true;
      }
    }
  }

  Future<void> _toggleConnection() async {
    if (_isConnecting) return;

    if (_isConnected) {
      try {
        await _bluetoothService.disconnect();
        if (!mounted) return;
        setState(() {
          _isConnected = false;
          _isRelayOn = null;
          _temperatureCelsius = null;
          _humidityPercent = null;
          _dhtSensorError = false;
        });
        _addLog(
          'Verbindung zu ${RelayScreenConfig.deviceName} getrennt.',
          isStatus: true,
        );
      } catch (error) {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _isRelayOn = null;
            _temperatureCelsius = null;
            _humidityPercent = null;
            _dhtSensorError = false;
          });
          _addLog('Trennen fehlgeschlagen: $error', isStatus: true);
        }
      }
      return;
    }

    if (!isValidBluetoothAddress(_deviceAddress)) {
      _addLog(
        'Bitte zuerst eine gültige Bluetooth-Adresse speichern.',
        isStatus: true,
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _isRelayOn = null;
      _temperatureCelsius = null;
      _humidityPercent = null;
      _dhtSensorError = false;
    });
    _addLog(
      'Verbinde mit ${RelayScreenConfig.deviceName} ($_deviceAddress)...',
      isStatus: true,
    );

    try {
      await _bluetoothService.connect(_deviceAddress);
      if (!mounted) return;
      if (!_bluetoothService.isConnected) {
        throw StateError('Die Verbindung wurde unmittelbar getrennt.');
      }
      setState(() => _isConnected = true);
      _addLog(
        'Verbunden. Warte auf den Relaisstatus des Arduino.',
        isStatus: true,
      );
    } catch (error) {
      if (mounted) _addLog('Verbindung fehlgeschlagen: $error', isStatus: true);
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _setRelayState(bool turnOn) async {
    final command = turnOn ? RelayCommand.turnOn : RelayCommand.turnOff;
    try {
      await _bluetoothService.sendCommand(command);
      if (mounted) {
        _addLog(
          'Befehl "${PumpProtocol.encode(command)}" gesendet; '
          'warte auf Arduino-Bestätigung.',
          isSend: true,
        );
      }
    } catch (error) {
      if (mounted) {
        if (!_bluetoothService.isConnected) {
          setState(() {
            _isConnected = false;
            _isRelayOn = null;
            _temperatureCelsius = null;
            _humidityPercent = null;
            _dhtSensorError = false;
          });
        }
        _addLog('Sendefehler: $error', isStatus: true);
      }
    }
  }

  String get _relayStatusText => switch (_isRelayOn) {
    true => 'PUMPE LÄUFT (1)',
    false => 'PUMPE AUS (0)',
    null => 'ZUSTAND UNBEKANNT',
  };

  String get _dhtStatusText {
    if (_dhtSensorError) return 'Sensorfehler (DHT11)';
    if (_temperatureCelsius == null || _humidityPercent == null) {
      return _isConnected ? 'Warte auf Messwerte' : 'Nicht verbunden';
    }
    return 'Aktuelle Messwerte';
  }

  @override
  void dispose() {
    unawaited(_disposeBluetooth());
    unawaited(_disposeMqtt());
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _disposeBluetooth() async {
    try {
      await _eventSubscription?.cancel();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'water pump bluetooth events',
          context: ErrorDescription('while cancelling the event subscription'),
        ),
      );
    }
    await _disconnectOnDispose();
  }

  Future<void> _disconnectOnDispose() async {
    try {
      await _bluetoothService.disconnect();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'water pump bluetooth service',
          context: ErrorDescription('while disconnecting during disposal'),
        ),
      );
    }
  }

  Future<void> _disposeMqtt() async {
    try {
      await _mqttPublisher.disconnect();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'water pump mqtt publisher',
          context: ErrorDescription('while disconnecting during disposal'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConnect =
        !_isLoadingAddress &&
        isValidBluetoothAddress(_deviceAddress) &&
        !_isConnecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relais-Steuerung'),
        actions: [
          IconButton(
            tooltip: 'Bluetooth-Gerät einstellen',
            onPressed: _isConnected || _isConnecting
                ? null
                : _editDeviceAddress,
            icon: const Icon(Icons.settings_bluetooth),
          ),
          IconButton(
            tooltip: _isMqttConnected
                ? 'MQTT verbunden – Einstellungen'
                : 'MQTT einstellen',
            onPressed: _isMqttConnecting ? null : _editMqttSettings,
            icon: Icon(
              _isMqttConnected ? Icons.cloud_done : Icons.cloud_upload,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _isConnected
                  ? _toggleConnection
                  : (canConnect ? _toggleConnection : null),
              icon: Icon(
                _isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
              ),
              label: Text(
                _isConnecting
                    ? 'Verbindet...'
                    : (_isConnected ? 'Trennen' : 'Verbinden'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _isConnected
                    ? Colors.red.shade700
                    : Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zielgerät: ${RelayScreenConfig.deviceName} '
                      '(${_deviceAddress.isEmpty ? "nicht konfiguriert" : _deviceAddress})',
                    ),
                    Text('Plattform: ${_bluetoothService.platformInfo}'),
                    Text(
                      'Verbindung: ${_isConnected ? "Verbunden" : "Nicht verbunden"}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isConnected
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.water_drop,
                      size: 48,
                      color: _isRelayOn == true
                          ? Colors.blue
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _relayStatusText,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _isRelayOn == true
                                ? Colors.blue.shade800
                                : Colors.grey.shade700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isConnected
                              ? () => _setRelayState(true)
                              : null,
                          icon: const Icon(Icons.power),
                          label: const Text('EIN (1)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isConnected
                              ? () => _setRelayState(false)
                              : null,
                          icon: const Icon(Icons.power_off),
                          label: const Text('AUS (0)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              key: const Key('dht11-reading-card'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DHT11-Messwerte',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Temperatur: '
                            '${_temperatureCelsius?.toStringAsFixed(1) ?? "--"} °C',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Luftfeuchtigkeit: '
                            '${_humidityPercent?.toStringAsFixed(1) ?? "--"} %',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(_dhtStatusText, key: const Key('dht11-status')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Protokoll:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Text(
                    _logs[index],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: RelayScreenConfig.logFontSize,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceAddressDialog extends StatefulWidget {
  const _DeviceAddressDialog({required this.initialAddress});

  final String initialAddress;

  @override
  State<_DeviceAddressDialog> createState() => _DeviceAddressDialogState();
}

class _DeviceAddressDialogState extends State<_DeviceAddressDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialAddress,
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bluetooth-Gerät'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('device-address-input'),
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Bluetooth-Adresse',
            hintText: 'AA:BB:CC:DD:EE:FF',
          ),
          validator: (value) {
            final candidate = value?.trim() ?? '';
            return isValidBluetoothAddress(candidate)
                ? null
                : 'Gib eine gültige MAC-Adresse ein.';
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('save-device-address'),
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, _controller.text.trim().toUpperCase());
            }
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _MqttSettingsDialog extends StatefulWidget {
  const _MqttSettingsDialog({this.initialSettings});

  final MqttConnectionSettings? initialSettings;

  @override
  State<_MqttSettingsDialog> createState() => _MqttSettingsDialogState();
}

class _MqttSettingsDialogState extends State<_MqttSettingsDialog> {
  late final TextEditingController _hostController = TextEditingController(
    text: widget.initialSettings?.host ?? '',
  );
  late final TextEditingController _portController = TextEditingController(
    text: '${widget.initialSettings?.port ?? 1883}',
  );
  late final TextEditingController _usernameController = TextEditingController(
    text: widget.initialSettings?.username ?? '',
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.initialSettings?.password ?? '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validatePort(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null || port < 1 || port > 65535) {
      return 'Gib einen Port zwischen 1 und 65535 ein.';
    }
    return null;
  }

  String? _validateUsername(String? value) {
    if ((value?.trim().isEmpty ?? true) &&
        _passwordController.text.isNotEmpty) {
      return 'Für ein Passwort wird auch ein Benutzername benötigt.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value?.isEmpty ?? true) &&
        _usernameController.text.trim().isNotEmpty) {
      return 'Für diesen Broker wird ein Passwort benötigt.';
    }
    return null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      MqttConnectionSettings(
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('MQTT-Broker'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('mqtt-host-input'),
                  controller: _hostController,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Broker-Adresse',
                    hintText: 'z. B. 192.168.1.20',
                  ),
                  validator: (value) => value?.trim().isNotEmpty == true
                      ? null
                      : 'Gib die Laptop-IP oder den Broker-Host ein.',
                ),
                TextFormField(
                  key: const Key('mqtt-port-input'),
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                  validator: _validatePort,
                ),
                TextFormField(
                  key: const Key('mqtt-username-input'),
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Benutzername (optional)',
                  ),
                  validator: _validateUsername,
                ),
                TextFormField(
                  key: const Key('mqtt-password-input'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Passwort (optional)',
                    helperText: 'Wird verschlüsselt auf dem Gerät gespeichert.',
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Passwort anzeigen'
                          : 'Passwort verbergen',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Auf dem Handy die Laptop-IP statt localhost verwenden. '
                  'Benutzername und Passwort können beide leer bleiben, '
                  'wenn der Broker anonyme Verbindungen erlaubt.',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('save-mqtt-settings'),
          onPressed: _save,
          child: const Text('Speichern und verbinden'),
        ),
      ],
    );
  }
}
