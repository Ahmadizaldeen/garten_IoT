# Kommunikationsprotokolle

Dieses Dokument beschreibt, wie die Android-App, der Arduino, das HC-06-Modul, der MQTT-Broker und das Browser-Dashboard miteinander kommunizieren.

## Datenweg

```text
DHT11 ──> Arduino ──Bluetooth SPP──> Android-App ──MQTT/WLAN──> Mosquitto
Relais <── Arduino <──Bluetooth SPP── Android-App                 │
                                                                  └──MQTT über WebSockets──> Browser-Dashboard
```

Der Arduino spricht direkt mit der Android-App über eine serielle Bluetooth-Verbindung (SPP). Die App dient als Gateway: Sie verarbeitet die Bluetooth-Zeilen und veröffentlicht Messwerte sowie bestätigte Relaiszustände per MQTT. Das Browser-Dashboard verbindet sich nicht mit Bluetooth, sondern abonniert die MQTT-Nachrichten.

## Bluetooth SPP

Die serielle Verbindung läuft mit **9600 Baud**. Die App sendet einzelne ASCII-Zeichen. Für Befehle ist kein Zeilenende erforderlich. Antworten des Arduino sind zeilenbasiert und enden mit einem Zeilenumbruch.

### Befehle von der App an den Arduino

| ASCII | Bedeutung |
| --- | --- |
| `1` | Relais einschalten |
| `0` | Relais ausschalten |
| `?` | Aktuellen Relaiszustand abfragen |

Der lokale Taster am Arduino schaltet das Relais unabhängig von der App um. Auch in diesem Fall sendet der Arduino eine Statusmeldung.

### Meldungen vom Arduino an die App

| Beispiel | Bedeutung |
| --- | --- |
| `STATE:1` | Arduino meldet das Relais als eingeschaltet |
| `STATE:0` | Arduino meldet das Relais als ausgeschaltet |
| `DHT:23.0,56.0` | Temperatur in °C, danach relative Luftfeuchtigkeit in % |
| `DHT:ERR` | DHT11-Messung fehlgeschlagen oder Messwert außerhalb des gültigen Bereichs |

Die DHT11-Messung wird alle zwei Sekunden ausgeführt. Temperatur und Luftfeuchtigkeit werden mit einer Nachkommastelle übertragen. `STATE:1` und `STATE:0` beschreiben den vom Arduino gesetzten Relaiszustand; es gibt keine unabhängige elektrische Rückmeldung von der Pumpe.

Beim Start setzt die Firmware das Relais auf AUS und meldet den Zustand. Beim Verbindungsaufbau fragt die App mit `?` erneut nach. Der Status wird erst nach einer `STATE:`-Rückmeldung als bestätigt angezeigt oder an MQTT weitergeleitet.

### Zeilenverarbeitung

Bluetooth-Daten können in mehreren Paketen eintreffen. Die App puffert deshalb empfangene Bytes, bis ein Zeilenumbruch vorliegt, und wertet erst dann eine vollständige Meldung aus. Ein einzelnes `\r` oder `\n` wird beim Parsen entfernt. Der Empfangspuffer wird verworfen, wenn er ohne vollständigen Zeilenumbruch mehr als 128 Zeichen erreicht.

Die App akzeptiert DHT11-Werte nur in plausiblen Grenzen:

- Temperatur: 0 bis 50 °C
- Luftfeuchtigkeit: 0 bis 100 %

Unvollständige, falsch formatierte oder ungültige Zeilen werden nicht als Messwerte angezeigt.

## MQTT

Die Android-App veröffentlicht die über Bluetooth empfangenen Daten an den konfigurierten Broker. Standardport für MQTT/TCP ist **1883**. Host, Port und Zugangsdaten werden in den App-Einstellungen verwaltet; das Passwort wird durch `flutter_secure_storage` geschützt gespeichert.

### Topics und Payloads

| Topic | QoS | Retained | Payload-Beispiel | Inhalt |
| --- | ---: | --- | --- | --- |
| `garten/pumpe/telemetry` | 0 | Ja | `{"temperature_c":23.0,"humidity_percent":56.0}` | DHT11-Messwerte |
| `garten/pumpe/status` | 0 | Ja | `{"relay_on":true}` | Vom Arduino bestätigter Relaiszustand |

Ein retained-Wert bleibt beim Broker gespeichert. Ein neu verbundener Client erhält dadurch den zuletzt veröffentlichten Wert, auch wenn gerade keine neue Messung eintrifft.

Die App veröffentlicht Statusänderungen erst nach einer bestätigenden Arduino-Meldung. Beim Wiederverbinden mit MQTT veröffentlicht sie einen bereits bekannten Relaisstatus erneut. Messwerte erscheinen weiterhin in der App, auch wenn der Broker nicht erreichbar ist.

### MQTT im Browser

Browser können keine normale MQTT/TCP-Verbindung zu Port 1883 öffnen. Das HTML-Dashboard verwendet MQTT.js über WebSockets. Mosquitto muss dazu zusätzlich einen WebSocket-Listener anbieten (in dieser Installation standardmäßig Port **9001**). Das Dashboard abonniert standardmäßig `garten/pumpe/#`, damit es beide Topics erhält.

Das Dashboard erwartet für Sensorwerte die JSON-Schlüssel `temperature_c` und `humidity_percent`, für den Status `relay_on`. Ein bestätigter Wechsel des Relaiszustands wird zusätzlich als farbiger `1`- oder `0`-Marker in der Pumpenrelais-Spalte dargestellt.

## Sicherheit und Verbindung

- Für MQTT in der Android-App muss als Broker-Host die im lokalen Netzwerk erreichbare Adresse des Laptops eingetragen werden, nicht `localhost`.
- Broker-Zugangsdaten nicht in Quellcode, Screenshots oder öffentliche Dokumentation eintragen.
- `ws://` und MQTT auf Port 1883 übertragen Daten unverschlüsselt. Nur in einem vertrauenswürdigen, lokalen Netzwerk verwenden.
- WebSocket- und MQTT-Ports nicht ungeschützt ins Internet freigeben. Authentifizierung und gegebenenfalls Broker-ACLs müssen Lesen und Schreiben auf die benötigten Topics begrenzen.
- Für Zugriff über unsichere Netzwerke TLS (`wss://` beziehungsweise TLS-geschütztes MQTT) konfigurieren.

## Fehlersuche

| Symptom | Prüfen |
| --- | --- |
| App meldet Sensorfehler | DHT11-Versorgung, Masse, Datenleitung an D8 und gegebenenfalls Pull-up-Widerstand prüfen. |
| Relaisstatus bleibt unbekannt | Firmware mit `STATE:`-Antworten verwenden; Bluetooth-Verbindung und `?`-Abfrage prüfen. |
| App zeigt Messwerte, MQTT-Client erhält nichts | Broker-Host, Port, Authentifizierung, Netzwerk und Schreibrechte der App prüfen. |
| Dashboard verbindet sich nicht | WebSocket-Listener, URL (`ws://<Laptop-IP>:9001`), Browser-Zugangsdaten und Leserechte prüfen. |
| Dashboard zeigt Sensorwerte, aber keinen Pumpenstatus | Topic `garten/pumpe/#` abonnieren und prüfen, ob `garten/pumpe/status` veröffentlicht wird. |
