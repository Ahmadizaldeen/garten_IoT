# Hardware und Verkabelung

Dieses Dokument listet die Hardware des Systems auf und beschreibt die Verbindungen zwischen Arduino, Sensor, Bluetooth-Modul und Relais. Die tatsächliche Pinbelegung der Firmware steht in `arduino/006_v1/006_v1.ino`.

## Komponenten

### Steuerung und Sensoren

| Komponente | Aufgabe | Hinweise |
| --- | --- | --- |
| Arduino Uno oder kompatibles 5-V-Board | Führt die Firmware aus und verbindet Sensor, Taster, Bluetooth und Relais. | Der Sketch verwendet `SoftwareSerial` und die Pins D2, D7, D8, D10, D11 und D13. |
| DHT11-Sensor oder DHT11-Modul | Misst Temperatur und relative Luftfeuchtigkeit. | Datenleitung an D8. Ein Modul hat häufig einen integrierten Pull-up; ein nackter Sensor benötigt je nach Schaltung typischerweise einen Pull-up-Widerstand. |
| HC-06 oder kompatibles Bluetooth-Classic-SPP-Modul | Serielle Funkverbindung zwischen Arduino und Android- beziehungsweise Linux-App. | Firmware-Kommunikation: 9600 Baud. Versorgung und zulässige UART-Pegel des konkreten Breakout-Boards prüfen. |
| Taster (Schließer) | Schaltet das Relais lokal um. | Zwischen D2 und GND; Firmware aktiviert `INPUT_PULLUP` und entprellt 50 ms. |
| Eingebaute LED an D13 | Zeigt an, dass der Taster gedrückt ist. | Bei einem Uno ist dafür normalerweise keine zusätzliche LED erforderlich. |

### Lastschaltung und weitere Geräte

| Komponente | Aufgabe | Hinweise |
| --- | --- | --- |
| Relaismodul, passend zu Logik und Last | Schaltet die Pumpenversorgung. | Steuereingang an D7. Der Sketch verwendet ein aktiv-LOW-Relais: LOW = EIN, HIGH = AUS. Modulspannung, Triggerpegel und Kontaktbelastbarkeit müssen zur Anwendung passen. |
| Pumpe und passende externe Stromversorgung | Die Pumpe ist die geschaltete Last. | Nicht über den 5-V-Ausgang des Arduino versorgen. Versorgung und Relaiskontakte müssen für Spannung und Anlaufstrom der Pumpe ausgelegt sein. |
| Android-Handy oder Linux-PC mit Bluetooth Classic | Bedient das Relais und empfängt die Sensordaten. | Das HC-06 muss im Betriebssystem gekoppelt sein; die App verbindet sich anschließend per MAC-Adresse über Bluetooth Classic SPP/RFCOMM. |
| Laptop/PC mit Mosquitto und WLAN | Nimmt MQTT-Nachrichten von der App entgegen. | Die App und der Laptop müssen sich im erreichbaren Netzwerk befinden. |
| Browser auf Laptop oder Handy | Zeigt Sensorwerte und Relaisstatus im Dashboard. | Verbindet sich über MQTT-WebSockets, nicht über Bluetooth. |
| USB-Kabel, Steckleitungen und gegebenenfalls Breadboard | Programmierung und Verbindung der Kleinspannungs-Schaltung. | Für Pumpen- oder Netzstrom keine Steckplatine verwenden. |

## Anschlussplan Arduino

| Arduino-Anschluss | Verbindung |
| --- | --- |
| D2 | Tasterkontakt; anderer Tasterkontakt an GND |
| D7 | Steuereingang (`IN`) des Relaismoduls |
| D8 | DHT11-Datenleitung (`DATA`/`S`) |
| D10 (SoftwareSerial RX) | HC-06 TX |
| D11 (SoftwareSerial TX) | HC-06 RX, über passende Pegelanpassung |
| D13 | Eingebaute LED des Arduino Uno |
| 5V / GND | Versorgung und Masse von Sensor und Modulen entsprechend deren Datenblatt |

Die UART-Leitungen werden gekreuzt: Arduino RX empfängt von Modul TX; Arduino TX sendet an Modul RX. Ein 5-V-Arduino-Ausgang darf nicht ungeprüft an den RX-Eingang eines 3,3-V-UART-Moduls angeschlossen werden. Für D11 → HC-06 RX einen geeigneten Pegelwandler oder Spannungsteiler verwenden. Die zulässige Versorgung am VCC-Pin hängt vom konkreten HC-06-Breakout ab; dessen Dokumentation beachten.

Beim DHT11 gilt die Beschriftung auf dem konkreten Sensor oder Modul. Bei einem typischen Modul sind die Anschlüsse als `S`/`DATA`, `VCC` und `GND` markiert. Nicht allein von der physischen Reihenfolge der Pins ausgehen. Bei einem nackten DHT11 ist ein Pull-up zwischen Datenleitung und Versorgung erforderlich, falls er nicht bereits in der Schaltung vorhanden ist.

## Versorgung, Masse und Relais

- Arduino, DHT11 und die Logikseite des HC-06 benötigen eine geeignete Versorgung. Prüfe vor dem Anschluss die zulässigen Spannungen jedes Moduls.
- Sensor, Bluetooth und Arduino benötigen eine gemeinsame Signalmasse, sofern die jeweilige Modulschaltung nichts anderes vorgibt.
- Die Relais-Steuerseite entsprechend dem Datenblatt des Moduls anschließen. Bei optisch isolierten Modulen können separate Masse-/Versorgungskonzepte gelten; nicht pauschal Isolationsbrücken setzen.
- Die Pumpe wird über die Relaiskontakte mit einer dafür geeigneten externen Versorgung geschaltet. Niemals den Pumpenstrom durch den Arduino führen.
- Für induktive Lasten und Netzspannung sind passende Schutzmaßnahmen, Sicherung, Isolation, Gehäuse und ein ausreichend dimensioniertes Relais erforderlich.

**Achtung:** Arbeiten an Netzspannung können lebensgefährlich sein. Netzspannungsverdrahtung nur durch eine qualifizierte Person und entsprechend den örtlichen Vorschriften ausführen lassen. Das Relaismodul muss für Pumpenspannung, Dauerstrom und Anlaufstrom geeignet sein. Eine Softwareanzeige des Relaiszustands beweist nicht, dass die Pumpe tatsächlich läuft.

## Inbetriebnahme-Checkliste

1. Arduino zunächst nur mit USB versorgen und den Sketch `arduino/006_v1/006_v1.ino` laden.
2. DHT11-Versorgung, GND und DATA an D8 kontrollieren. Für die Arduino-Bibliotheken werden **DHT sensor library** und **Adafruit Unified Sensor** benötigt.
3. HC-06 mit gekreuzten TX/RX-Leitungen anschließen und den RX-Pegel schützen. Die serielle Geschwindigkeit ist 9600 Baud.
4. Relais-Steuersignal an D7 anschließen. Vor Anschluss einer Pumpe prüfen, dass der Zustand beim Start AUS ist; der Sketch behandelt LOW als EIN.
5. Taster zwischen D2 und GND anschließen. Die eingebaute LED an D13 leuchtet während des Tastendrucks.
6. Bluetooth-Modul mit Android beziehungsweise Linux koppeln, die Geräteadresse in der App einstellen und den Status sowie die DHT11-Werte testen. Unter Linux wird BlueZ benötigt; die App nutzt RFCOMM-Kanal 1.
7. Erst nach Prüfung von Relaiskontakt, Lastdaten, externer Versorgung und Schutzmaßnahmen die Pumpe anschließen.
8. Für MQTT Laptop und Handy ins erreichbare Netzwerk bringen und Mosquitto so konfigurieren, dass die App schreiben und das Dashboard per WebSocket lesen darf.

## Firmware-Zuordnung

Die verwendeten Pin-Konstanten und Betriebsparameter:

| Firmware-Konstante | Wert | Bedeutung |
| --- | ---: | --- |
| `BUTTON_PIN` | D2 | Lokaler Taster, aktiv LOW |
| `RELAY_PIN` | D7 | Relais-Steuerausgang, aktiv LOW |
| `BUTTON_LED_PIN` | D13 | Tasteranzeige |
| `DHT_PIN` | D8 | DHT11-Datenleitung |
| `BLUETOOTH_RX_PIN` | D10 | SoftwareSerial-Empfang |
| `BLUETOOTH_TX_PIN` | D11 | SoftwareSerial-Senden |
| `DHT_READ_INTERVAL_MS` | 2000 ms | Messintervall des DHT11 |
