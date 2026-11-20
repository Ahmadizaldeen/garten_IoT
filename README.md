# Garten – Wasserpumpen-Steuerung

Eine Flutter-App zur manuellen Steuerung einer Wasserpumpe über ein Bluetooth-Classic-Relais. Die Android-App verbindet sich mit einem HC-06-Modul und sendet zum Schalten der Pumpe die Zeichen `1` (EIN) beziehungsweise `0` (AUS).

## Voraussetzungen

- Flutter SDK mit Dart SDK `^3.13.2` (siehe `pubspec.yaml`)
- Android-Gerät mit Bluetooth Classic
- HC-06-Modul beziehungsweise ein kompatibles Bluetooth-SPP-Gerät, das die Befehle `1` und `0` versteht
- Das Gerät muss im Android-System gekoppelt sein

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

Den Sketch `arduino/006_v1.ino` mit der Arduino IDE auf das passende Board laden. Die Pinbelegung ist:

| Anschluss | Pin |
| --- | --- |
| Taster (gegen GND, `INPUT_PULLUP`) | 2 |
| Relais | 7 |
| Taster-LED | 13 |
| Arduino SoftwareSerial RX/TX | 10/11 |

Verbinde HC-06 TX mit Arduino-Pin 10 und Arduino-Pin 11 mit HC-06 RX. Bei 5-V-Boards muss die Arduino-TX-Leitung zum HC-06-RX-Eingang passend pegelangepasst werden. Der Relaisausgang ist aktiv LOW und wird beim Start auf AUS gesetzt. Das Bluetooth-Modul kommuniziert mit 9600 Baud. Die App benötigt die aktualisierte Sketch-Version, damit sie den Relaiszustand abfragen und anzeigen kann.

## Verwendung

1. Das HC-06-Modul einschalten und in den Android-Bluetooth-Einstellungen koppeln.
2. In der App über das Bluetooth-Symbol die HC-06-MAC-Adresse speichern.
3. Auf **Verbinden** tippen und den Verbindungsstatus kontrollieren.
4. Mit **EIN (1)** oder **AUS (0)** den jeweiligen Befehl senden.
5. Im Protokollbereich werden Arduino-Zustandsmeldungen, Verbindungsereignisse und Befehle mit Zeitstempel angezeigt.
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

Der Arduino meldet Änderungen sowohl nach App-Befehlen als auch nach Betätigung des lokalen Tasters. Beim Verbindungsaufbau fragt die App den aktuellen Zustand ab. Ein älterer Sketch ohne `?`-Abfrage und `STATE:`-Antworten kann zwar `1` und `0` empfangen, liefert der App aber keine Zustandsbestätigung.

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
- `lib/bt_service_web.dart` – Web-Implementierung, die Bluetooth Classic als nicht unterstützt meldet
- `lib/bt_service_stub.dart` – Fallback für nicht implementierte Plattformen
- `lib/pump_protocol.dart` – Kodierung der App-Befehle und Auswertung der Arduino-Statuszeilen
- `lib/device_address_store.dart` – Validierung und lokale Speicherung der HC-06-Adresse
- `arduino/006_v1/006_v1.ino` – Arduino-Firmware mit Tasterentprellung, Relaissteuerung und Bluetooth-Statusantworten
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
