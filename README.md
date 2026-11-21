# Garten – Wasserpumpen-Steuerung

Eine Flutter-App zur manuellen Steuerung einer Wasserpumpe über ein Bluetooth-Classic-Relais. Die Android-App verbindet sich mit einem HC-06-Modul, sendet zum Schalten der Pumpe die Zeichen `1` (EIN) beziehungsweise `0` (AUS) und zeigt Temperatur sowie Luftfeuchtigkeit eines DHT11-Sensors an.

## Vertiefende Dokumentation

- [README_Protokolle.md](README_Protokolle.md) – Bluetooth- und MQTT-Nachrichtenformate sowie deren Ablauf
- [README_Hardware.md](README_Hardware.md) – Komponenten, Arduino-Pinbelegung, Verkabelung und Sicherheitshinweise

## Voraussetzungen

- Flutter SDK mit Dart SDK `^3.13.2` (siehe `pubspec.yaml`)
- Android-Gerät mit Bluetooth Classic
- HC-06-Modul beziehungsweise ein kompatibles Bluetooth-SPP-Gerät, das die Befehle `1` und `0` versteht
- Das Gerät muss im Android-System gekoppelt sein
- Arduino-Bibliotheken **DHT sensor library** und **Adafruit Unified Sensor**

Die HC-06-Adresse wird beim ersten Start in der App unter **Bluetooth-Gerät einstellen** eingetragen und lokal gespeichert. Die App listet gekoppelte Geräte nicht automatisch auf.

## Installation und Start

Im Projektverzeichnis ausführen:

```shell
flutter pub get
flutter run
```

Zum Erstellen einer Android-APK:

```shell
flutter build apk
```

## Arduino vorbereiten

Den Sketch `arduino/006_v1/006_v1.ino` mit der Arduino IDE auf das passende Board laden. Die Arduino-Bibliotheken **DHT sensor library** und **Adafruit Unified Sensor** müssen über den Bibliotheksverwalter installiert sein. Verbinde den DHT11 mit Versorgung und Masse; bei einem nackten Sensor ist je nach Aufbau ein Pull-up-Widerstand an der Datenleitung erforderlich. Die Pinbelegung ist:

| Anschluss | Pin |
| --- | --- |
| Taster (gegen GND, `INPUT_PULLUP`) | 2 |
| Relais | 7 |
| Taster-LED | 13 |
| DHT11-Datenleitung | 8 |
| Arduino SoftwareSerial RX/TX | 10/11 |

Verbinde HC-06 TX mit Arduino-Pin 10 und Arduino-Pin 11 mit HC-06 RX. Bei 5-V-Boards muss die Arduino-TX-Leitung zum HC-06-RX-Eingang passend pegelangepasst werden. Der Relaisausgang ist aktiv LOW und wird beim Start auf AUS gesetzt. Das Bluetooth-Modul kommuniziert mit 9600 Baud. Die App benötigt die aktualisierte Sketch-Version, damit sie den Relaiszustand abfragen und die DHT11-Messwerte empfangen kann.

## Verwendung

1. Das HC-06-Modul einschalten und in den Android-Bluetooth-Einstellungen koppeln.
2. In der App über das Bluetooth-Symbol die HC-06-MAC-Adresse speichern.
3. Auf **Verbinden** tippen und den Verbindungsstatus kontrollieren.
4. Mit **EIN (1)** oder **AUS (0)** den jeweiligen Befehl senden.
5. Temperatur und Luftfeuchtigkeit werden in der DHT11-Karte angezeigt. Im Protokollbereich erscheinen Arduino-Zustandsmeldungen, Verbindungsereignisse und Befehle mit Zeitstempel.
6. Über **Trennen** die Verbindung beenden.

Die Schaltflächen sind nur bei bestehender Verbindung aktiviert. Die App zeigt den vom Arduino gemeldeten Relaiszustand an; eine tatsächliche Rückmeldung der Pumpe wird nicht ausgewertet. Für einen sicheren Betrieb müssen Relais, Pumpe und Stromversorgung unabhängig von der App fachgerecht abgesichert sein.

## Bluetooth-Protokoll

Die App sendet einzelne ASCII-Zeichen ohne Zeilenende. Der Arduino antwortet mit zeilenbasierten Statusmeldungen:

| Richtung | Nachricht | Bedeutung |
| --- | --- | --- |
| App → Arduino | `1` | Relais einschalten |
| App → Arduino | `0` | Relais ausschalten |
| App → Arduino | `?` | Aktuellen Relaiszustand abfragen |
| Arduino → App | `STATE:1` | Relais ist eingeschaltet |
| Arduino → App | `STATE:0` | Relais ist ausgeschaltet |
| Arduino → App | `DHT:23.0,56.0` | Temperatur in °C und relative Luftfeuchtigkeit in % |
| Arduino → App | `DHT:ERR` | DHT11-Messung fehlgeschlagen |

Der Arduino meldet Änderungen sowohl nach App-Befehlen als auch nach Betätigung des lokalen Tasters und sendet DHT11-Messwerte alle zwei Sekunden. Beim Verbindungsaufbau fragt die App den aktuellen Relaiszustand ab; die nächste Sensormessung folgt innerhalb von zwei Sekunden. Ein älterer Sketch ohne `?`-Abfrage und `STATE:`-Antworten kann zwar `1` und `0` empfangen, liefert der App aber keine Zustandsbestätigung.

## MQTT-Veröffentlichung

Die Android-App kann die über Bluetooth empfangenen DHT11-Messwerte an einen MQTT-Broker weiterleiten. Über das Wolkensymbol lassen sich Broker-Host, Port, Benutzername und Passwort eintragen. Für Mosquitto auf einem Laptop müssen Laptop und Handy im selben WLAN sein; in der App ist die lokale Laptop-IP statt `localhost` einzutragen. Das Passwort wird mit `flutter_secure_storage` geschützt abgelegt.

Die App veröffentlicht retained JSON-Nachrichten mit QoS 0 auf diesen Topics:

- `garten/pumpe/telemetry` für DHT11-Messwerte:

```json
{"temperature_c":23.0,"humidity_percent":56.0}
```

- `garten/pumpe/status` für den vom Arduino bestätigten Relaiszustand:

```json
{"relay_on":true}
```

Der Status wird erst nach einer Arduino-Rückmeldung (`STATE:1` oder `STATE:0`) veröffentlicht. Er zeigt den geschalteten Relaiszustand an, nicht eine unabhängige elektrische Rückmeldung der Pumpe.

Die MQTT-Verbindung wird beim App-Start mit gespeicherten Einstellungen aufgebaut und bei Verbindungsverlust automatisch wiederhergestellt. Bluetooth-Daten werden auch dann weiter in der App angezeigt, wenn MQTT nicht verfügbar ist. Der MQTT-Broker muss vom Handy aus erreichbar sein; Port 1883 sollte nicht ungeschützt ins Internet freigegeben werden.

### Live-Dashboard im Browser

Die Datei [MQTT Matrix.html](MQTT%20Matrix.html) zeigt Temperatur, Luftfeuchtigkeit und Relaiszustand live an und behält die Matrix-Ansicht bei. Sie abonniert standardmäßig `garten/pumpe/#`; Browser können nicht direkt über MQTT/TCP auf Port 1883 zugreifen, Mosquitto muss deshalb zusätzlich MQTT über WebSockets anbieten.

Für ein Dashboard, das auf demselben Laptop wie Mosquitto läuft, prüfe zuerst, ob bereits ein WebSocket-Listener existiert. Nur falls keiner vorhanden ist, ergänze in `mosquitto.conf` einen lokalen Listener und starte Mosquitto neu:

```conf
listener 9001 127.0.0.1
protocol websockets
```

Existiert bereits ein Listener auf Port 9001, lege keinen zweiten an. Für reinen Zugriff vom selben Laptop sollte der vorhandene Listener an `127.0.0.1` gebunden sein.

Bestehende Authentifizierungseinstellungen des Brokers sollen aktiv bleiben. Öffne die HTML-Datei über XAMPP, zum Beispiel unter `http://localhost/garten/MQTT%20Matrix.html`, und trage die Mosquitto-Zugangsdaten ein. Die Seite speichert sie nicht selbst. Sie verwendet standardmäßig `ws://localhost:9001` und das Topic `garten/pumpe/#`. Wenn du ACLs verwendest, erlaube der App das Schreiben auf beide Topics und dem Browser-Benutzer das Lesen von `garten/pumpe/#`. Wenn du die Seite auf einem anderen Gerät öffnest, ersetze `localhost` durch die Laptop-IP und konfiguriere den Listener so, dass er im lokalen Netzwerk erreichbar ist. Öffne den WebSocket-Port nicht ungeschützt im Internet.

## Ablauf

Das Ablaufdiagramm liegt als Mermaid-Quelldatei vor: [ablauf.mmd](ablauf.mmd).
Die ausführliche Erklärung des Datenflusses beim Schalten, einschließlich der Rückmeldung vom Arduino, steht in [datenfluss.html](datenfluss.html).

## Konfiguration

Die Konstante `deviceName` sowie die Anzeigeoptionen liegen in `lib/relay_dashboard_screen.dart` (`RelayScreenConfig`). Die Bluetooth-Adresse wird dagegen in den App-Einstellungen verwaltet und mit `shared_preferences` lokal gespeichert.

| Einstellung | Standardwert | Bedeutung |
| --- | --- | --- |
| `deviceName` | `HC-06` | Anzeigename des Zielgeräts |
| `showSend` | `true` | Gesendete Befehle im Protokoll anzeigen |
| `showStatus` | `true` | Statusmeldungen im Protokoll anzeigen |
| `showTimestamp` | `true` | Zeitstempel vor Protokolleinträgen anzeigen |
| `autoScroll` | `true` | Protokoll automatisch zum neuesten Eintrag scrollen |
| `logFontSize` | `14.0` | Schriftgröße des Protokolls |

## Aufbau

- `lib/main.dart` – App-Einstieg
- `lib/app.dart` – App-Widget, Theme und Startseite
- `lib/relay_dashboard_screen.dart` – Benutzeroberfläche, Verbindung, Relaissteuerung und Protokoll
- `lib/bt_service.dart` – gemeinsame Bluetooth-Service-Schnittstelle und Zustandsereignisse
- `lib/bt_service_android.dart` – Bluetooth-Classic-SPP-Verbindung auf Android; fordert die Bluetooth-Verbindungsberechtigung an
- `lib/mqtt_publisher.dart` – MQTT-Verbindung, sichere Zugangsdatenablage, DHT11-Telemetrie und Relaisstatus
- `MQTT Matrix.html` – MQTT-WebSocket-Dashboard für Temperatur, Luftfeuchtigkeit und Relaisstatus
- `lib/bt_service_web.dart` – Web-Implementierung, die Bluetooth Classic als nicht unterstützt meldet
- `lib/bt_service_stub.dart` – Fallback für nicht implementierte Plattformen
- `lib/pump_protocol.dart` – Kodierung der App-Befehle und Auswertung von Arduino-Status- und DHT11-Zeilen
- `lib/device_address_store.dart` – Validierung und lokale Speicherung der HC-06-Adresse
- `arduino/006_v1/006_v1.ino` – Arduino-Firmware mit Tasterentprellung, Relaissteuerung und Bluetooth-Telemetrie des DHT11
- `android/` – Android-Projekt und Bluetooth-Berechtigungsdeklarationen
- `test/` – Flutter-Tests

## Plattformhinweise

Die Bluetooth-Steuerung ist für Android mit Bluetooth Classic ausgelegt. Webbrowser können das HC-06/SPP-Protokoll in dieser Implementierung nicht verwenden. Andere Plattformen verwenden derzeit den nicht unterstützten Fallback. Für die Arduino-Steuerung ist ein HC-06-kompatibles SPP-Modul mit 9600 Baud erforderlich.

## Qualitätssicherung

```shell
flutter analyze
flutter test
```

`test/widget_test.dart` prüft die Adressvalidierung, den Verbindungsaufbau, die Zustandsbestätigung, EIN-/AUS-Befehle, das Trennen und den Fehlerfall beim Verbindungsaufbau. `test/pump_protocol_test.dart` deckt die Kodierung und Auswertung des seriellen Protokolls ab.
