# MQTT-Broker und Matrix einrichten

Diese Anleitung beschreibt Mosquitto auf einem Linux-PC sowie die Verbindung
der Android- oder Linux-App und des Browser-Dashboards. Die App empfängt die
Arduino-Daten per Bluetooth und veröffentlicht sie beim Broker:

```text
Arduino/HC-06 --Bluetooth--> App --MQTT/TCP--> Mosquitto --WebSockets--> MQTT Matrix
```

Die Matrix verbindet sich nicht direkt mit dem HC-06 und schaltet die Pumpe
nicht. Sie zeigt die vom Arduino über die App gemeldeten Werte an.
Nachrichtenformate und Topics stehen in [README_Protokolle.md](README_Protokolle.md).

## 1. Broker auf Linux installieren und prüfen

Auf Debian, Ubuntu oder Linux Mint:

```shell
sudo apt install mosquitto mosquitto-clients
sudo systemctl enable --now mosquitto
sudo systemctl status mosquitto --no-pager
```

Der Dienst sollte `active (running)` anzeigen. Weitere Diagnose:

```shell
sudo journalctl -u mosquitto -n 50 --no-pager
sudo ss -ltnp | grep -E ':1883|:9001'
sudo grep -RniE '^[[:space:]]*(listener|protocol|allow_anonymous|password_file|acl_file|include_dir|per_listener_settings)' \
  /etc/mosquitto/mosquitto.conf /etc/mosquitto/conf.d/
```

Die Konfiguration liegt üblicherweise in `/etc/mosquitto/mosquitto.conf` und
den über `include_dir` eingebundenen Dateien. Ports können abweichend
konfiguriert sein; die Einstellungen des tatsächlich verwendeten Brokers sind
maßgeblich. Veröffentliche keine Passwörter oder andere Zugangsdaten, wenn du
Diagnoseausgaben weitergibst.

## 2. Listener und Zugriff einrichten

| Verbindung | Üblicher Port | Protokoll |
| --- | ---: | --- |
| Android- oder Linux-App zum Broker | 1883 | MQTT über TCP |
| Matrix im Browser zum Broker | 9001 | MQTT über WebSockets |

Für Android muss Port 1883 auf einer vom Handy erreichbaren Adresse lauschen.
Ermittle die WLAN-IP des PCs mit `hostname -I`; das Ergebnis kann mehrere
Adressen enthalten. `127.0.0.1:1883` in der `ss`-Ausgabe ist nur lokal
erreichbar. `0.0.0.0:1883` lauscht auf allen IPv4-Schnittstellen; eine
explizite WLAN-IP beschränkt den Listener auf diese Adresse.

Ein mögliches Beispiel für einen MQTT-Listener auf einer festen WLAN-IP und
einen nur lokal erreichbaren WebSocket-Listener:

```conf
listener 1883 192.168.1.50
protocol mqtt

listener 9001 127.0.0.1
protocol websockets
```

`192.168.1.50` ist ein Beispiel und muss durch die tatsächliche, möglichst
feste IP des Linux-PCs ersetzt werden. Bearbeite bestehende Listener, statt
einen bereits verwendeten Port erneut anzulegen. Wenn erstmals explizite
Listener definiert werden, muss auch der benötigte MQTT/TCP-Listener
ausdrücklich konfiguriert werden; verlasse dich nicht auf einen vorherigen
Standard-Listener. Ist die Matrix auf einem anderen Gerät, benötigt auch der
WebSocket-Listener eine für dieses Gerät erreichbare Adresse; dann muss die
Matrix `ws://<PC-IP>:9001` verwenden.

Die Listener-Beispiele ersetzen **nicht** die Authentifizierung: Bestehende
Benutzer-, Passwort- und ACL-Einstellungen beibehalten und bei
`per_listener_settings` für jeden Listener entsprechend prüfen. Die App
benötigt Schreibrechte auf `garten/pumpe/telemetry` und `garten/pumpe/status`,
die Matrix Leserechte auf diese Topics. Nur wenn der Broker anonyme
Verbindungen ausdrücklich erlaubt, können Benutzername und Passwort leer
bleiben. Nach Änderungen den Dienst neu starten und das Ergebnis prüfen:

```shell
sudo systemctl restart mosquitto
sudo systemctl status mosquitto --no-pager
sudo journalctl -u mosquitto -n 50 --no-pager
```

Bei aktiver Firewall muss TCP-Port 1883 für das lokale Netzwerk erreichbar
sein; Port 9001 nur, wenn der Browser auf einem anderen Gerät läuft. Keine
Ports ungeschützt ins Internet freigeben. Die App verwendet derzeit
unverschlüsseltes MQTT/TCP; auch `ws://` ist unverschlüsselt. Diese
Konfiguration nur in einem vertrauenswürdigen Netzwerk nutzen. `wss://` kann
für die Matrix am Broker eingerichtet werden; MQTT über TLS ist in der
aktuellen App nicht konfigurierbar.

## 3. App mit dem Broker verbinden

1. Das App-Gerät und den Broker-PC in dasselbe erreichbare Netzwerk bringen.
   Bei einem Gast-WLAN kann eine Client-Isolation die Verbindung verhindern.
2. In der App das **Wolkensymbol** und die MQTT-Einstellungen öffnen.
3. Für Android die WLAN-IP des Broker-PCs, zum Beispiel `192.168.1.50`,
   als **Broker-Adresse** eintragen. Kein `http://` oder `ws://` angeben.
   `localhost` beziehungsweise `127.0.0.1` bezeichnet auf Android das Handy,
   nicht den PC. Läuft die Linux-App auf demselben PC wie Mosquitto, kann
   `127.0.0.1` verwendet werden.
4. Den MQTT/TCP-Port, üblicherweise `1883`, und gegebenenfalls Benutzername
   und Passwort eintragen. Die App verlangt beide Zugangsdaten zusammen oder
   beide leer.
5. Einstellungen speichern und im App-Protokoll nach der Meldung suchen,
   dass die MQTT-Verbindung hergestellt wurde.
6. Die App mit dem HC-06 verbinden. Die App fragt den Relaiszustand ab und
   veröffentlicht bestätigte Statusmeldungen sowie gültige DHT11-Werte.

Das HC-06 erlaubt normalerweise nur eine aktive Bluetooth-Verbindung. Vor
einem Wechsel von der Linux-App zu Android gegebenenfalls die bestehende
Verbindung in der Linux-App trennen.

## 4. MQTT Matrix verbinden

Die Datei [MQTT Matrix.html](MQTT%20Matrix.html) im Browser öffnen. Bei Bedarf
über einen lokalen Webserver bereitstellen, zum Beispiel im Projektverzeichnis:

```shell
python3 -m http.server 8000 --bind 127.0.0.1
```

Anschließend auf demselben PC `http://127.0.0.1:8000/MQTT%20Matrix.html`
öffnen. Der Server bleibt bis `Strg+C` aktiv. Die Seite lädt MQTT.js von einem
externen CDN; dafür muss der Browser die Bibliothek erreichen können.

| Feld | Wert bei lokalem Broker und Browser |
| --- | --- |
| Broker-URL | `ws://localhost:9001` |
| Topic | `garten/pumpe/#` |
| Benutzername und Passwort | Falls vom Broker verlangt |

Auf **Verbinden** klicken; dadurch werden die Demo-Daten ausgeschaltet.
Bei einem Browser auf einem anderen Gerät ist statt `localhost` die
Broker-PC-IP einzutragen und der WebSocket-Listener muss erreichbar sein.
Die Matrix zeigt Temperatur, Luftfeuchtigkeit und den bestätigten
Relaiszustand. `Retained`-Nachrichten können beim Verbinden auch ältere
Werte anzeigen und beweisen keine aktuelle Bluetooth-Verbindung.

## 5. Nachrichten und Fehler prüfen

Zum Beobachten der Topics auf dem Broker-PC:

```shell
mosquitto_sub -h 127.0.0.1 -p 1883 -t 'garten/pumpe/#' -v
```

Bei aktivierter Authentifizierung einen passenden Benutzer und ein Passwort
gemäß der lokalen Mosquitto-Client-Dokumentation angeben; Passwörter nicht in
öffentliche Ausgaben oder Shell-Verläufe schreiben. Falls der MQTT-Listener
an eine bestimmte WLAN-IP statt `127.0.0.1` gebunden ist, diese IP mit `-h`
verwenden. Der Befehl läuft bis `Strg+C`.

| Problem | Prüfen |
| --- | --- |
| Android erreicht den Broker nicht | WLAN-IP statt `localhost`, Listener-Adresse, Port 1883, Firewall und Client-Isolation prüfen. |
| Verbindung wird abgelehnt | Broker-Logs, Benutzername, Passwort und Listener-Authentifizierung prüfen. |
| Matrix verbindet sich nicht | Port 9001, WebSocket-Listener, URL, Zugangsdaten und Laden der MQTT.js-Bibliothek prüfen. |
| Matrix ist verbunden, aber zeigt keine neuen Werte | Bluetooth-Verbindung, Arduino-Daten, MQTT-Verbindung und Topic-Rechte prüfen. |
| `mosquitto_sub` zeigt nichts | Broker-Adresse, Authentifizierung, Leserechte und App-Protokoll kontrollieren. |
