# ssh2keys

```
ssh2keys – SSH-Pubkey auf Linux-Hosts und Dropbear-Router verteilen.

Projekt:     ssh2keys
Modul:       README.md
Version:     1.7.0
Stand:       2026-08-21
Abhaengig:   Bash >= 4; OpenSSH (ssh); sshpass (Passwort-Login); optional putty-tools/puttygen (-ppk)
Bezug:       requirements.txt (leer – keine Python-Pakete)
Lizenz:      MIT
Upstream:    –
Erstellt mit: Cursor Grok 4.6
Autor:       (FFHB) / RadioBBS
```

Verteilt einen lokalen SSH-Pubkey auf Linux-Hosts und Dropbear-Router.
Zuerst Root (`/root/.ssh/authorized_keys`), danach vorhandene Passwd-User;
doppelte Keys werden entfernt, ein bereits vorhandener Key nicht erneut
eingetragen. Ohne direkten Root-Login erfolgt der Eintrag per sudo/su.

## Voraussetzungen

- Linux, macOS oder WSL (Bash >= 4)
- OpenSSH-Client (`ssh`)
- `sshpass` fuer Passwort-Login (`-P`)
- optional `puttygen` (Paket `putty-tools`) fuer `-ppk`
- lokale Pubkey-Datei (Standard: `./ffhb.pub`, per `--key-file` aenderbar)

Windows: das Skript selbst laeuft unter Bash (WSL/Git-Bash). Die Unit-Tests
nutzen Python 3 (Standardbibliothek).

## Installation

```bat
cd /d "%USERPROFILE%\Documents\Cursor\GIT-Projects\ssh2keys"
python -m pip install -r requirements.txt
```

Keine Pip-Pakete noetig. Auf dem Host, von dem aus verteilt wird:

```bash
# Debian/Ubuntu
sudo apt-get install -y openssh-client sshpass putty-tools
chmod +x ./ssh2keys.sh
```

## Aufruf

```bash
./ssh2keys.sh --help
./ssh2keys.sh --version
```

Beispiele:

```bash
./ssh2keys.sh 192.168.178.11 -U pi -P 'Password' -A --key-file ./ffhb.pub --log
./ssh2keys.sh 192.168.1.1 -U root -ppk ./id.ppk -A --log
./ssh2keys.sh 192.168.1.1 -U pi -ppk ./id.ppk -A --log -E
./ssh2keys.sh 192.168.178.11 -U pi -P 'Password' -R --marker ffhb@FFHB --log
```

Wichtige Parameter:

| Parameter | Typ | Standard | Beschreibung |
|---|---|---|---|
| host | Hostname/IP | (Pflicht) | Zielsystem |
| `-U` | str | `root` | Login-User, falls Root nicht geht |
| `-P` | str | (Abfrage) | Login-/sudo-Passwort; bei verschluesseltem PPK auch Passphrase |
| `-ppk` | Pfad | – | PuTTY-Private-Key fuer den Login |
| `-A` / `-R` | Flag | `-A` | Hinzufuegen bzw. Marker entfernen |
| `--key-file` | Pfad | `./ffhb.pub` | lokale Pubkey-Datei |
| `--marker` | str | `ffhb@FFHB` | Such-/Loeschmarker |
| `--log` | Flag | aus | Logging in `ssh2keys.log` |
| `-E` / `--Ende` | Flag | aus | am Ende auf Taste warten |

## Risiken

- Das Skript **aendert** `authorized_keys` auf dem Ziel (Root, User, optional Dropbear).
- Homes werden **nicht** angelegt; fehlende Home-Verzeichnisse fuehren zum Abbruch fuer diesen User.
- Passwoerter erscheinen nicht im Log; `-P` steht trotzdem in der Prozessliste – bevorzugt PPK oder interaktive Abfrage.
- `-R` entfernt alle Zeilen mit dem Marker, nicht nur den aktuellen Key.
- Pubkey-, PPK- und Logdateien gehoeren nicht ins Git (siehe `.gitignore`).

Rollback: Key mit `-R` und demselben `--marker` wieder entfernen, oder die
betroffene `authorized_keys` aus einem Backup zurueckspielen.

## Tests

Ohne Netz und ohne echte Hosts:

```bat
cd /d "%USERPROFILE%\Documents\Cursor\GIT-Projects\ssh2keys"
python -m unittest tests.test_ssh2keys
```

## Lizenz

MIT – siehe `LICENSE`.
