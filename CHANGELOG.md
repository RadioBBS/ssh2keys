# ssh2keys – Aenderungsprotokoll des Produkts.

```
ssh2keys – Release-Historie (CHANGELOG).

Projekt:     ssh2keys
Modul:       CHANGELOG.md
Version:     1.7.0
Stand:       2026-08-21
Abhaengig:   Bash >= 4; OpenSSH (ssh); sshpass (Passwort-Login); optional putty-tools/puttygen (-ppk)
Bezug:       requirements.txt (leer – keine Python-Pakete)
Lizenz:      MIT
Upstream:    –
Erstellt mit: Cursor Grok 4.6
Autor:       (FFHB) / RadioBBS
```

Produkt-Changelog in Nutzersprache. Die Datei-Historie im Skriptkopf bleibt zusaetzlich (Styleguide).

## 1.7.0 – 2026-08-21

### Added

- Eigenes Git-Projekt unter `GIT-Projects/ssh2keys` mit README, LICENSE, CHANGELOG, `.gitignore`, `requirements.txt` und Tests.
- `--version` nennt zusaetzlich die Programmbeschreibung.

### Changed

- Dateikopf nach Styleguide 1.5.2 (einheitliche Pflichtfelder, Autor `(FFHB) / RadioBBS`).

## 1.6.4 – 2026-08-04

### Fixed

- User-Liste nur aus Passwd-Konten; Waisen-Ordner unter `/home` werden uebersprungen.

## 1.6.3 – 2026-08-03

### Changed

- Auto-Scan `/home/*` wieder aktiv; Root bleibt fest `/root`; keine relativen Homes.

## 1.6.2 – 2026-08-03

### Changed

- Root fest `/root`; Auto-Scan voruebergehend zurueckgenommen.

## 1.6.1 – 2026-08-03

### Changed

- Erreichbarkeit vor SSH per `sudo ping`.

## 1.6.0 – 2026-08-03

### Added

- Unverschluesselte PPK ohne `-P`; Konsolenabfrage fuer Passwort/Passphrase.
- Ping und SSH-`ConnectTimeout`.

## 1.5.4 – 2026-08-03

### Changed

- Login als User: Root-`authorized_keys` komplett via sudo/su.

## 1.5.0 – 2026-08-03

### Added

- Deduplizierung; Key nur einfuegen, wenn er fehlt.
- Root via sudo/su; Dropbear `/etc/dropbear`.

## 1.0.0 – 2026-08-02

### Added

- Add/Remove, Logging, `--Ende`.

## 0.1.0 – 2019-05-09

### Added

- Entwurf: Key aus Datei auf Remote-Host verteilen.
