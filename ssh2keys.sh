#!/usr/bin/env bash
#
# ssh2keys – SSH-Pubkey auf Linux-Hosts und Dropbear-Router verteilen.
#
# Projekt:     ssh2keys
# Modul:       ssh2keys.sh
# Version:     1.7.0
# Stand:       2026-08-21
# Abhaengig:   Bash >= 4; OpenSSH (ssh); sshpass (Passwort-Login); optional putty-tools/puttygen (-ppk)
# Bezug:       requirements.txt (leer – keine Python-Pakete)
# Lizenz:      MIT
# Upstream:    –
# Erstellt mit: Cursor Grok 4.6
# Autor:       (FFHB) / RadioBBS
#
# Beschreibung
# ------------
# Prueft Root-Zugang, entfernt doppelte SSH-Keys in authorized_keys und
# traegt den Pubkey nur ein, wenn er fehlt. Ohne Root: Login als -U,
# Root-Eintrag per sudo/su. Erkennt Router/Dropbear (/etc/dropbear).
#
# Historie
# --------
# Version 0.1.0 – 2019-05-09 – Entwurf; Key aus /root/.ssh/ffhb.pub.
# Version 1.0.0 – 2026-08-02 – Style-Guide, Add/Remove, Logging/--Ende.
# Version 1.1.0 – 2026-08-02 – -U/-P/-ppk; User-Home.
# Version 1.2.0 – 2026-08-03 – -ppk Datei.ppk; Passphrase via -P.
# Version 1.2.1 – 2026-08-03 – Passwort als String; keyboard-interactive.
# Version 1.3.0 – 2026-08-03 – Login-Test; getent-Home; sudo/chmod.
# Version 1.4.0 – 2026-08-03 – Root-First; weitere User; sudo fuer root.
# Version 1.5.0 – 2026-08-03 – Deduplizierung; nur einfuegen wenn fehlend;
#   Root via sudo/su; Dropbear /etc/dropbear; ausfuehrliches Log/Konsole.
# Version 1.5.1 – 2026-08-03 – Root-Home fest /root (nie /home/root).
# Version 1.5.2 – 2026-08-03 – Remote-Skript POSIX (kein [[ unter dash);
#   Pubkey-Dekodierung ohne Fallback-Wipe; sudo-Fehler sichtbar.
# Version 1.5.3 – 2026-08-03 – Nie Home anlegen; nur .ssh + authorized_keys;
#   Ablauf: Home pruefen, .ssh, Datei, temp. Rechte, Dedup, Key add.
# Version 1.5.4 – 2026-08-03 – Login als User: Root-authorized_keys
#   komplett via sudo/su (Lesen+Schreiben unter /root).
# Version 1.6.0 – 2026-08-03 – PPK ohne Passphrase ohne -P; Konsolen-
#   Abfrage fuer Passwort/Passphrase; Ping + SSH-ConnectTimeout.
# Version 1.6.1 – 2026-08-03 – Erreichbarkeit per sudo ping.
# Version 1.6.2 – 2026-08-03 – Root fest /root; kein Auto-Scan (zurueckgenommen).
# Version 1.6.3 – 2026-08-03 – Auto-Scan /home/* wie 1.6.1; Root fest /root;
#   keine relativen Homes (kein Dummy/.ssh).
# Version 1.6.4 – 2026-08-04 – User-Liste nur Passwd-Konten; Waisen wie
#   /home/dummy werden ignoriert/uebersprungen.
# Version 1.7.0 – 2026-08-21 – GIT-Projects, Styleguide-Dateien, GitHub.
#
# Aufruf / Nutzung
# ----------------
#   ./ssh2keys.sh --help
#   ./ssh2keys.sh --version
#   ./ssh2keys.sh 192.168.178.11 -U pi -P 'Password' -A --key-file ./ffhb.pub --log
#

VERSION="1.7.0"
VERSION_DATUM="2026-08-21"
ANZEIGE_NAME="ssh2keys"
SKRIPTNAME="${0##*/}"
MEIN_NAME="ssh2keys"
LOGDATEI="./${MEIN_NAME}.log"
END_PROMPT="Programmende: Hit any Key or Enter"
DROPBEAR_AUTH="/etc/dropbear/authorized_keys"
SSH_CONNECT_TIMEOUT=8
PING_WAIT_SEC=2

ziel_host=""
remote_user="root"
login_password=""
ppk_datei=""
ppk_passphrase=""
openssh_tmp_key=""
ip_familie=""
aktion="add"
key_datei="./ffhb.pub"
schluessel_marker="ffhb@FFHB"
PUBLICSSHKEY=""
logging_aktiv=false
warte_am_ende=false
ssh_opts=()
ssh_ziel=""
root_zugang=false
login_account=""
ist_router=false

zeitstempel() {
	#
	# Beschreibung: Zeitstempel fuer Logzeilen.
	# Parameter: keine
	# Rueckgabewert: YYYY-MM-DD HH:MM:SS
	# Fehlerfaelle: date fehlt
	# Beispiel: zeitstempel
	#
	date '+%Y-%m-%d %H:%M:%S'
}

log_nachricht() {
	#
	# Beschreibung: Logzeile schreiben, falls Logging aktiv.
	# Parameter: $1 = Stufe/Text
	# Rueckgabewert: keines
	# Fehlerfaelle: Schreibfehler ignoriert
	# Beispiel: log_nachricht "INFO start"
	#
	[[ "$logging_aktiv" != true ]] && return 0
	printf '%s %s\n' "$(zeitstempel)" "$1" >> "$LOGDATEI" 2>/dev/null || true
}

info_meldung() {
	#
	# Beschreibung: Info auf Konsole und ins Log.
	# Parameter: $1 = Text
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: info_meldung "Start"
	#
	echo "$SKRIPTNAME: $1"
	log_nachricht "INFO  $1"
}

schritt_meldung() {
	#
	# Beschreibung: Ausfuehrlicher Fortschritt (Konsole + Log).
	# Parameter: $1 = Text
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: schritt_meldung "Pruefe Root"
	#
	echo "$SKRIPTNAME: --> $1"
	log_nachricht "SCHRITT $1"
}

debug_meldung() {
	#
	# Beschreibung: Detailausgabe zur Nachverfolgung.
	# Parameter: $1 = Text
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: debug_meldung "Datei X"
	#
	echo "$SKRIPTNAME:    $1"
	log_nachricht "DETAIL $1"
}

fehler_melden() {
	#
	# Beschreibung: Fehler auf stderr und ins Log.
	# Parameter: $1 = Text
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: fehler_melden "x"
	#
	echo "$SKRIPTNAME: FEHLER: $1" >&2
	log_nachricht "FEHLER $1"
}

warnung_melden() {
	#
	# Beschreibung: Warnung auf Konsole und Log.
	# Parameter: $1 = Text
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: warnung_melden "skip"
	#
	echo "$SKRIPTNAME: WARNUNG: $1" >&2
	log_nachricht "WARNUNG $1"
}

beende_mit_fehler() {
	#
	# Beschreibung: Zentraler Abbruch mit Exit-Code.
	# Parameter: $1 = Code, $2 = Meldung
	# Rueckgabewert: beendet Skript
	# Fehlerfaelle: final
	# Beispiel: beende_mit_fehler 2 "fehlt"
	#
	fehler_melden "$2"
	log_nachricht "===== ABBRUCH Exit=$1 ====="
	exit "$1"
}

bereinige_tmp_key() {
	#
	# Beschreibung: Loescht temporaeren OpenSSH-Key aus PPK-Konvertierung.
	# Parameter: keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: bereinige_tmp_key
	#
	[[ -n "$openssh_tmp_key" && -f "$openssh_tmp_key" ]] || return 0
	rm -f "$openssh_tmp_key"
	openssh_tmp_key=""
}

warte_auf_programmende() {
	#
	# Beschreibung: Pause bei --Ende / -E.
	# Parameter: keine
	# Rueckgabewert: keines
	# Fehlerfaelle: nicht-interaktiv still
	# Beispiel: warte_auf_programmende
	#
	[[ "$warte_am_ende" != true ]] && return 0
	[[ ! -t 0 ]] && return 0
	echo "$END_PROMPT"
	read -r -n 1 -s || true
	echo
}

aufraeumen_beim_exit() {
	#
	# Beschreibung: EXIT-Trap: Temp-Key und optionale Ende-Pause.
	# Parameter: keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: trap aufraeumen_beim_exit EXIT
	#
	bereinige_tmp_key
	warte_auf_programmende
}

zeige_version() {
	#
	# Beschreibung: Version, Datum und Programmbeschreibung.
	# Parameter: keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: zeige_version
	#
	echo "$ANZEIGE_NAME $VERSION ($VERSION_DATUM)"
	echo "Verteilt einen SSH-Pubkey auf Linux-Hosts und Dropbear-Router."
}

zeige_hilfe() {
	#
	# Beschreibung: Hilfe mit Parametern und Beispielen.
	# Parameter: keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine
	# Beispiel: zeige_hilfe
	#
	cat << EOF
ssh2keys $VERSION ($VERSION_DATUM)
Verteilt einen SSH-Pubkey: Root zuerst, dann User; Deduplizierung; Dropbear.

Verwendung:
  $0 [-4|-6] <host> [-U USER] [-P PASS] [-ppk DATEI.ppk] [-A|-R] --log
  $0 --help | -h
  $0 --version

Parameter:
  host                 Zielhost (Hostname oder IP), Pflicht
  -U <user>            Benutzer-Login falls Root nicht geht (Standard: root)
  -P <text>            Login-/sudo-Passwort; bei verschluesseltem PPK auch Passphrase
  -ppk, --ppk <datei>  PuTTY-Private-Key (.ppk) fuer den Login (ohne Passphrase OK)
  -4 / -6              SSH nur IPv4 bzw. IPv6
  -A                   Pruefen/Deduplizieren/Hinzufuegen (Standard)
  -R                   Schluessel (Marker) entfernen
  --key-file <pfad>    Lokale Pubkey-Datei (Standard: ./ffhb.pub)
  --marker TEXT        Such-/Loeschmarker (Standard: ffhb@FFHB)
  --log                Ausfuehrliches Logging in ${MEIN_NAME}.log
  -h, --help           Diese Hilfe
  --version            Version und Datum
  -E, --Ende           Am Ende auf Tastendruck warten

Hinweise:
  Fehlt -P und ein Passwort/eine Passphrase wird benoetigt: Abfrage auf der Konsole.
  Unverschluesselte .ppk brauchen keine Passphrase; -P gilt dann nur fuer sudo/su.
  Vor SSH: kurzer sudo ping (Warnung bei Ausfall) und ConnectTimeout=${SSH_CONNECT_TIMEOUT}s.

Ablauf (-A):
  1) Erreichbarkeit (sudo ping) und Root-Zugang testen
  2) authorized_keys unter /root/.ssh (fest) pruefen/deduplizieren/ergaenzen
  3) Weitere User unter /home/*; Root ohne Direct-Login via sudo/su
  4) Falls /etc/dropbear vorhanden: Router/Dropbear-Keys ebenfalls pflegen

Beispiele:
  $0 192.168.178.11 -U pi -P 'Password' -A --key-file ./ffhb.pub --log
  $0 192.168.1.1 -U root -ppk ./id.ppk -A --log
  $0 192.168.1.1 -U pi -ppk ./id.ppk -A --log
EOF
}

lade_pubkey() {
	#
	# Beschreibung: Liest den Pubkey aus der lokalen Key-Datei.
	# Parameter: keine
	# Rueckgabewert: setzt PUBLICSSHKEY
	# Fehlerfaelle: Datei fehlt oder leer
	# Beispiel: lade_pubkey
	#
	schritt_meldung "Lade Pubkey aus: $key_datei"
	[[ -f "$key_datei" ]] || beende_mit_fehler 3 "Key-Datei nicht gefunden: $key_datei"
	PUBLICSSHKEY="$(tr -d '\r' < "$key_datei" | head -n 1)"
	[[ -n "$PUBLICSSHKEY" ]] || beende_mit_fehler 5 "Key-Datei ist leer: $key_datei"
	debug_meldung "Pubkey-Typ: $(awk '{print $1}' <<< "$PUBLICSSHKEY")"
	debug_meldung "Pubkey-Kommentar/Rest: $(awk '{$1=$2=""; sub(/^ /,""); print}' <<< "$PUBLICSSHKEY")"
}

konvertiere_ppk_nach_openssh() {
	#
	# Beschreibung: Wandelt .ppk via puttygen in einen Temp-OpenSSH-Key um.
	# Parameter: keine
	# Rueckgabewert: setzt openssh_tmp_key
	# Fehlerfaelle: puttygen/PPK/Passphrase
	# Beispiel: konvertiere_ppk_nach_openssh
	#
	local pass_file="" err_file="" phrase="" enc="" rc=0
	schritt_meldung "Konvertiere PPK: $ppk_datei"
	command -v puttygen >/dev/null 2>&1 \
		|| beende_mit_fehler 4 "puttygen fehlt (Paket putty-tools fuer -ppk)."
	[[ -f "$ppk_datei" ]] || beende_mit_fehler 3 "PPK-Datei nicht gefunden: $ppk_datei"

	enc="$(grep -i '^Encryption:' "$ppk_datei" 2>/dev/null | head -n 1 \
		| sed 's/^[Ee]ncryption:[[:space:]]*//' | tr -d '\r' | sed 's/[[:space:]]*$//')"
	debug_meldung "PPK Encryption-Feld: '${enc:-?}'"

	openssh_tmp_key="$(mktemp)"
	chmod 600 "$openssh_tmp_key"
	err_file="$(mktemp)"

	# Unverschluesselt: niemals --old-passphrase (sonst kann puttygen Phrase verlangen)
	if [[ -z "$enc" || "$enc" == "none" ]]; then
		debug_meldung "PPK ohne Passphrase – konvertiere ohne Phrase"
		if ! puttygen "$ppk_datei" -O private-openssh -o "$openssh_tmp_key" \
			>"$err_file" 2>&1; then
			debug_meldung "puttygen: $(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
			rm -f "$err_file"
			bereinige_tmp_key
			beende_mit_fehler 8 "PPK-Konvertierung fehlgeschlagen (Datei/puttygen?)."
		fi
		rm -f "$err_file"
		info_meldung "PPK erfolgreich konvertiert (ohne Passphrase)."
		return 0
	fi

	# Verschluesselt: Phrase aus ppk_passphrase, -P, sonst Konsole
	if [[ -n "$ppk_passphrase" ]]; then
		phrase="$ppk_passphrase"
	elif [[ -n "$login_password" ]]; then
		phrase="$login_password"
		debug_meldung "Nutze -P als PPK-Passphrase"
	else
		frage_geheimtext "PPK-Passphrase fuer $ppk_datei: " phrase
		ppk_passphrase="$phrase"
	fi
	[[ -n "$phrase" ]] || {
		rm -f "$err_file"
		bereinige_tmp_key
		beende_mit_fehler 8 "PPK ist verschluesselt – Passphrase fehlt."
	}

	pass_file="$(mktemp)"
	chmod 600 "$pass_file"
	printf '%s' "$phrase" > "$pass_file"
	puttygen "$ppk_datei" -O private-openssh -o "$openssh_tmp_key" \
		--old-passphrase "$pass_file" >"$err_file" 2>&1
	rc=$?
	if [[ "$rc" -ne 0 ]]; then
		debug_meldung "puttygen: $(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
		frage_geheimtext "PPK-Passphrase erneut: " phrase
		ppk_passphrase="$phrase"
		if [[ -z "$phrase" ]]; then
			rm -f "$pass_file" "$err_file"
			bereinige_tmp_key
			beende_mit_fehler 8 "PPK-Konvertierung fehlgeschlagen (Passphrase?)."
		fi
		printf '%s' "$phrase" > "$pass_file"
		puttygen "$ppk_datei" -O private-openssh -o "$openssh_tmp_key" \
			--old-passphrase "$pass_file" >"$err_file" 2>&1
		rc=$?
		if [[ "$rc" -ne 0 ]]; then
			rm -f "$pass_file" "$err_file"
			bereinige_tmp_key
			beende_mit_fehler 8 "PPK-Konvertierung fehlgeschlagen (Passphrase?)."
		fi
	fi
	rm -f "$pass_file" "$err_file"
	info_meldung "PPK erfolgreich konvertiert."
}

frage_geheimtext() {
	#
	# Beschreibung: Liest Passwort/Passphrase verdeckt von der Konsole.
	# Parameter: $1 = Prompt, $2 = Variablenname (Nameref via printf -v)
	# Rueckgabewert: setzt die genannte Variable
	# Fehlerfaelle: kein TTY
	# Beispiel: frage_geheimtext "Passwort: " login_password
	#
	local prompt="$1"
	local __ziel="$2"
	local __wert=""
	if [[ ! -t 0 ]]; then
		beende_mit_fehler 1 "Kein -P und kein Terminal fuer Abfrage ($prompt)."
	fi
	# Prompt auf stderr, damit Pipelines stdout sauber bleiben
	printf '%s' "$SKRIPTNAME: $prompt" >&2
	IFS= read -r -s __wert || true
	printf '\n' >&2
	printf -v "$__ziel" '%s' "$__wert"
}

stelle_login_passwort_sicher() {
	#
	# Beschreibung: Stellt sicher, dass login_password gesetzt ist (sonst Abfrage).
	# Parameter: $1 = Kurzgrund fuer Prompt
	# Rueckgabewert: keines; setzt login_password
	# Fehlerfaelle: leer / kein TTY
	# Beispiel: stelle_login_passwort_sicher "SSH-Login"
	#
	local grund="${1:-Login}"
	if [[ -z "$login_password" ]]; then
		frage_geheimtext "Passwort ($grund): " login_password
	fi
	[[ -n "$login_password" ]] \
		|| beende_mit_fehler 1 "Kein Passwort angegeben ($grund)."
}

pruefe_host_erreichbar() {
	#
	# Beschreibung: Kurzer Ping via sudo vor SSH; warnt bei Ausfall (ICMP kann blockiert sein).
	# Parameter: keine
	# Rueckgabewert: 0 (SSH folgt mit ConnectTimeout)
	# Fehlerfaelle: ping/sudo fehlt -> ueberspringen
	# Beispiel: pruefe_host_erreichbar
	#
	local ping_ok=false
	schritt_meldung "Pruefe Erreichbarkeit von $ziel_host (sudo ping, max ~${PING_WAIT_SEC}s) ..."
	if ! command -v ping >/dev/null 2>&1; then
		warnung_melden "ping fehlt – ueberspringe Vorpruefung, SSH mit ConnectTimeout=${SSH_CONNECT_TIMEOUT}s."
		return 0
	fi
	if ! command -v sudo >/dev/null 2>&1; then
		warnung_melden "sudo fehlt – ueberspringe Ping-Vorpruefung, SSH mit ConnectTimeout=${SSH_CONNECT_TIMEOUT}s."
		return 0
	fi
	# Linux/iputils: -c -W (Sekunden); BusyBox oft -w; beides versuchen
	if sudo ping -c 1 -W "$PING_WAIT_SEC" "$ziel_host" >/dev/null 2>&1; then
		ping_ok=true
	elif sudo ping -c 1 -w "$PING_WAIT_SEC" "$ziel_host" >/dev/null 2>&1; then
		ping_ok=true
	fi
	if [[ "$ping_ok" == true ]]; then
		info_meldung "Ping OK: $ziel_host"
		return 0
	fi
	warnung_melden "Kein Ping von $ziel_host (ICMP ggf. blockiert). Versuche SSH mit ConnectTimeout=${SSH_CONNECT_TIMEOUT}s ..."
	log_nachricht "WARNUNG ping fail host=$ziel_host"
	return 0
}

pruefe_authentifizierung() {
	#
	# Beschreibung: PPK oder Passwort-Login vorbereiten; fehlende Secrets abfragen.
	# Parameter: keine
	# Rueckgabewert: keines
	# Fehlerfaelle: keine Auth-Methode
	# Beispiel: pruefe_authentifizierung
	#
	schritt_meldung "Pruefe Authentifizierungsparameter ..."
	if [[ -n "$ppk_datei" ]]; then
		debug_meldung "Auth-Methode: PPK ($ppk_datei)"
		konvertiere_ppk_nach_openssh
		return 0
	fi
	stelle_login_passwort_sicher "SSH ${remote_user}@${ziel_host}"
	command -v sshpass >/dev/null 2>&1 \
		|| beende_mit_fehler 4 "sshpass fehlt (fuer Passwort-Login)."
	debug_meldung "Auth-Methode: Passwort, Laenge=${#login_password}"
}

baue_ssh_optionen() {
	#
	# Beschreibung: Setzt globale ssh_opts (IP und Auth), ohne Zieluser.
	# Parameter: keine
	# Rueckgabewert: setzt ssh_opts
	# Fehlerfaelle: Host fehlt / Auth fehlt
	# Beispiel: baue_ssh_optionen
	#
	[[ -z "$ziel_host" ]] && beende_mit_fehler 2 "Host fehlt. Aufruf: $0 --help"
	pruefe_host_erreichbar
	pruefe_authentifizierung

	ssh_opts=()
	[[ -n "$ip_familie" ]] && ssh_opts+=("$ip_familie")
	ssh_opts+=(
		-o StrictHostKeyChecking=accept-new
		-o ConnectTimeout="$SSH_CONNECT_TIMEOUT"
		-o ConnectionAttempts=1
	)

	if [[ -n "$ppk_datei" ]]; then
		ssh_opts+=(
			-i "$openssh_tmp_key"
			-o IdentitiesOnly=yes
			-o BatchMode=yes
			-o PreferredAuthentications=publickey
		)
	else
		ssh_opts+=(
			-o PreferredAuthentications=keyboard-interactive,password
			-o PubkeyAuthentication=no
			-o PasswordAuthentication=yes
			-o KbdInteractiveAuthentication=yes
			-o NumberOfPasswordPrompts=3
		)
	fi
	debug_meldung "SSH-Optionen vorbereitet fuer Host $ziel_host (ConnectTimeout=${SSH_CONNECT_TIMEOUT}s)"
}

setze_ssh_ziel() {
	#
	# Beschreibung: Setzt ssh_ziel auf user@host.
	# Parameter: $1 = Benutzername
	# Rueckgabewert: setzt ssh_ziel / login_account
	# Fehlerfaelle: leerer Name
	# Beispiel: setze_ssh_ziel root
	#
	[[ -n "$1" ]] || beende_mit_fehler 2 "SSH-Benutzer fehlt."
	login_account="$1"
	ssh_ziel="${1}@${ziel_host}"
	debug_meldung "Aktives SSH-Ziel: $ssh_ziel"
}

ssh_remote() {
	#
	# Beschreibung: Fuehrt Remote-Befehl per SSH zum aktuellen ssh_ziel aus.
	# Parameter: ssh-Argumente nach Ziel
	# Rueckgabewert: Exit-Code von ssh
	# Fehlerfaelle: SSH/sshpass fehlgeschlagen
	# Beispiel: ssh_remote "echo OK"
	#
	if [[ -n "$ppk_datei" ]]; then
		ssh "${ssh_opts[@]}" "$ssh_ziel" "$@"
		return $?
	fi
	export SSHPASS
	printf -v SSHPASS '%s' "$login_password"
	sshpass -e ssh "${ssh_opts[@]}" "$ssh_ziel" "$@"
	local rc=$?
	unset SSHPASS
	return "$rc"
}

teste_login_als() {
	#
	# Beschreibung: Prueft SSH-Login als bestimmter Benutzer.
	# Parameter: $1 = Benutzername
	# Rueckgabewert: 0 bei Erfolg, 1 bei Fehlschlag
	# Fehlerfaelle: Verbindungsfehler
	# Beispiel: teste_login_als root && echo ok
	#
	local vorher="$ssh_ziel"
	local vorher_acc="$login_account"
	schritt_meldung "Teste SSH-Login als '$1'@${ziel_host} ..."
	setze_ssh_ziel "$1"
	if ssh_remote "echo LOGIN_OK" >/dev/null 2>&1; then
		info_meldung "Login OK: $1@$ziel_host"
		return 0
	fi
	warnung_melden "Login fehlgeschlagen: $1@$ziel_host"
	ssh_ziel="$vorher"
	login_account="$vorher_acc"
	return 1
}

pubkey_b64() {
	#
	# Beschreibung: Base64 des Pubkeys (eine Zeile).
	# Parameter: keine
	# Rueckgabewert: Base64 auf stdout
	# Fehlerfaelle: keine
	# Beispiel: pubkey_b64
	#
	printf '%s' "$PUBLICSSHKEY" | base64 | tr -d '\n'
}

has_sudo_flag() {
	#
	# Beschreibung: 1 wenn -P gesetzt (sudo/su moeglich), sonst 0.
	# Parameter: keine
	# Rueckgabewert: 0 oder 1 auf stdout
	# Fehlerfaelle: keine
	# Beispiel: has_sudo_flag
	#
	[[ -n "$login_password" ]] && echo 1 || echo 0
}

remote_skript_ensure_key() {
	#
	# Beschreibung: Remote-Skript (POSIX sh): Deduplizieren und Key eintragen.
	# Parameter: keine (Heredoc); \$1 Zieluser oder DROPBEAR
	# Rueckgabewert: Skripttext
	# Fehlerfaelle: keine
	# Beispiel: remote_skript_ensure_key | ssh ...
	#
	cat <<'EOF'
# POSIX sh (dash) - kein [[ ]]
set -e
TARGET="$1"
DROPBEAR_AUTH="${DROPBEAR_AUTH_PATH:-/etc/dropbear/authorized_keys}"

# Pubkey dekodieren (ohne [[, sonst wuerde Fallback den Key leeren)
PUBKEY=""
if command -v base64 >/dev/null 2>&1; then
	PUBKEY="$(printf '%s' "$PUBKEY_B64" | base64 -d 2>/dev/null)" || PUBKEY=""
	if [ -z "$PUBKEY" ]; then
		PUBKEY="$(printf '%s' "$PUBKEY_B64" | base64 --decode 2>/dev/null)" || PUBKEY=""
	fi
fi
if [ -z "$PUBKEY" ]; then
	echo "REMOTE FEHLER: Pubkey-Dekodierung fehlgeschlagen (PUBKEY_B64 leer/ungueltig)" >&2
	exit 20
fi

echo "REMOTE: starte Bearbeitung fuer Ziel='$TARGET' (Login-User=$(id -un 2>/dev/null || echo ?), uid=$(id -u 2>/dev/null || echo ?))"

is_uid0() {
	[ "$(id -u 2>/dev/null)" = "0" ]
}

priv_run() {
	if is_uid0; then
		"$@"
		return $?
	fi
	if [ "$HAS_SUDO" != "1" ]; then
		echo "REMOTE FEHLER: Kein -P fuer sudo/su" >&2
		return 1
	fi
	if command -v sudo >/dev/null 2>&1; then
		echo "REMOTE: sudo: $*"
		if printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@" ; then
			echo "REMOTE: sudo OK"
			return 0
		fi
		echo "REMOTE: sudo fehlgeschlagen: $*" >&2
	fi
	if command -v su >/dev/null 2>&1; then
		_cmd="$*"
		echo "REMOTE: su -c: $_cmd"
		if printf '%s\n' "$SUDO_PASS" | su - root -c "$_cmd" ; then
			echo "REMOTE: su OK"
			return 0
		fi
		echo "REMOTE: su fehlgeschlagen: $_cmd" >&2
	fi
	return 1
}

priv_sh() {
	_job="$(mktemp 2>/dev/null || echo /tmp/job.$$)"
	cat > "$_job"
	chmod 700 "$_job" 2>/dev/null || true
	echo "REMOTE: privilegiertes Skript: $_job"
	_rc=1
	if is_uid0; then
		sh "$_job"
		_rc=$?
	elif [ "$HAS_SUDO" = "1" ] && command -v sudo >/dev/null 2>&1; then
		echo "REMOTE: sudo sh $_job"
		if printf '%s\n' "$SUDO_PASS" | sudo -S -p '' sh "$_job"; then
			_rc=0
		else
			_rc=$?
			echo "REMOTE: sudo fehlgeschlagen (rc=$_rc), versuche su ..." >&2
			if command -v su >/dev/null 2>&1; then
				if printf '%s\n' "$SUDO_PASS" | su - root -c "sh '$_job'"; then
					_rc=0
				else
					_rc=$?
					echo "REMOTE: su fehlgeschlagen (rc=$_rc)" >&2
				fi
			fi
		fi
	elif [ "$HAS_SUDO" = "1" ] && command -v su >/dev/null 2>&1; then
		echo "REMOTE: su -c sh $_job"
		if printf '%s\n' "$SUDO_PASS" | su - root -c "sh '$_job'"; then
			_rc=0
		else
			_rc=$?
			echo "REMOTE: su fehlgeschlagen (rc=$_rc)" >&2
		fi
	else
		echo "REMOTE FEHLER: kein sudo/su oder kein -P" >&2
		_rc=1
	fi
	rm -f "$_job"
	return "$_rc"
}

home_of() {
	_u="$(printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	if [ "$_u" = "root" ]; then
		printf '/root\n'
		return 0
	fi
	_h=""
	if command -v getent >/dev/null 2>&1; then
		_h="$(getent passwd "$_u" | cut -d: -f6 || true)"
		_h="$(printf '%s' "$_h" | tr -d '\r\n')"
	fi
	if [ "$_h" = "/home/root" ] || [ "$_h" = "/home/root/" ]; then
		_h="/root"
	fi
	# Relatives/kaputtes Home (z.B. nur "Dummy") verwerfen
	case "$_h" in
		""|.*) _h="" ;;
		/*) ;;
		*) _h="" ;;
	esac
	if [ -n "$_h" ]; then
		printf '%s\n' "$_h"
	else
		printf '/home/%s\n' "$_u"
	fi
}

key_id_of_line() {
	printf '%s\n' "$1" | awk 'NF>=2 {print $1" "$2}'
}

PUBKEY_ID="$(key_id_of_line "$PUBKEY")"
echo "REMOTE: Ziel-Key-ID=${PUBKEY_ID}"
if [ -z "$PUBKEY_ID" ]; then
	echo "REMOTE FEHLER: Key-ID leer - Pubkey ungueltig" >&2
	exit 21
fi

# Kompletter Root-Job als Nicht-root (Login pi -> sudo/su): Lesen+Schreiben unter /root
process_root_via_priv() {
	_pkf="$(mktemp 2>/dev/null || echo /tmp/pk.$$)"
	printf '%s\n' "$PUBKEY" > "$_pkf"
	chmod 644 "$_pkf" 2>/dev/null || true
	echo "REMOTE: Root-authorized_keys via sudo/su (Login=$(id -un))"
	priv_sh <<ROOTJOB_EOF
set -e
PKF='$_pkf'
AUTH='/root/.ssh/authorized_keys'
SSHDIR='/root/.ssh'
PUBKEY=\$(cat "\$PKF")
PUBKEY_ID=\$(printf '%s\\n' "\$PUBKEY" | awk 'NF>=2 {print \$1" "\$2}')
MARKER='$MARKER'

echo "ROOTJOB: bearbeite \$AUTH"
if [ ! -d /root ]; then
	echo "ROOTJOB FEHLER: /root fehlt" >&2
	exit 10
fi
echo "ROOTJOB: 1) /root vorhanden (nicht anlegen)"
if [ ! -d "\$SSHDIR" ]; then
	mkdir -m 700 "\$SSHDIR"
	echo "ROOTJOB: 2) .ssh angelegt"
else
	chmod 700 "\$SSHDIR" 2>/dev/null || true
	echo "ROOTJOB: 2) .ssh vorhanden"
fi
if [ ! -f "\$AUTH" ]; then
	touch "\$AUTH"
	chmod 600 "\$AUTH"
	echo "ROOTJOB: 3) authorized_keys angelegt"
else
	echo "ROOTJOB: 3) authorized_keys vorhanden"
fi

TMP=\$(mktemp 2>/dev/null || echo /tmp/ak.\$\$)
BEFORE=\$(wc -l < "\$AUTH" | tr -d ' ')
awk 'NF<2{print;next} /^#/{print;next} /^[[:space:]]*\$/{print;next} {id=\$1" "\$2; if(!seen[id]++) print}' "\$AUTH" > "\$TMP"
AFTER=\$(wc -l < "\$TMP" | tr -d ' ')
mv "\$TMP" "\$AUTH"
chmod 600 "\$AUTH"
echo "ROOTJOB: 4) Dedup \$BEFORE -> \$AFTER"

if awk -v id="\$PUBKEY_ID" 'NF>=2{ if(\$1" "\$2==id) f=1 } END{ exit !f }' "\$AUTH"; then
	echo "ROOTJOB: 5) Key bereits vorhanden"
	rm -f "\$PKF"
	exit 0
fi
if [ -n "\$MARKER" ] && grep -Fq "\$MARKER" "\$AUTH" 2>/dev/null; then
	echo "ROOTJOB: 5) Marker bereits vorhanden"
	rm -f "\$PKF"
	exit 0
fi

echo "ROOTJOB: 6) Key einfuegen"
printf '%s\\n' "\$PUBKEY" >> "\$AUTH"
chmod 600 "\$AUTH"
chown root:root "\$AUTH" "\$SSHDIR" 2>/dev/null || true

TMP=\$(mktemp 2>/dev/null || echo /tmp/ak2.\$\$)
awk 'NF<2{print;next} /^#/{print;next} {id=\$1" "\$2; if(!seen[id]++) print}' "\$AUTH" > "\$TMP"
mv "\$TMP" "\$AUTH"
chmod 600 "\$AUTH"

if awk -v id="\$PUBKEY_ID" 'NF>=2{ if(\$1" "\$2==id) f=1 } END{ exit !f }' "\$AUTH"; then
	echo "ROOTJOB: 7) Key OK in \$AUTH"
	rm -f "\$PKF"
	exit 0
fi
echo "ROOTJOB FEHLER: Key nicht in \$AUTH" >&2
rm -f "\$PKF"
exit 13
ROOTJOB_EOF
	_rc=$?
	rm -f "$_pkf"
	return "$_rc"
}

dedupe_auth_file() {
	_file="$1"
	_tmp=""
	_before=0
	_after=0
	[ -f "$_file" ] || return 0
	_before="$(wc -l < "$_file" 2>/dev/null | tr -d ' ' || echo 0)"
	_tmp="$(mktemp 2>/dev/null || echo /tmp/ak.$$)"
	awk '
		/^[[:space:]]*$/ { print; next }
		/^#/ { print; next }
		NF < 2 { print; next }
		{
			id = $1 " " $2
			if (!seen[id]++) print
		}
	' "$_file" > "$_tmp" 2>/dev/null || {
		rm -f "$_tmp"
		echo "REMOTE: Deduplizierung fehlgeschlagen fuer $_file"
		return 1
	}
	_after="$(wc -l < "$_tmp" 2>/dev/null | tr -d ' ' || echo 0)"
	if [ "$_before" != "$_after" ]; then
		echo "REMOTE: Duplikate entfernt in $_file (Zeilen $_before -> $_after)"
		if mv "$_tmp" "$_file" 2>/dev/null; then
			chmod 600 "$_file" 2>/dev/null || priv_run chmod 600 "$_file" || true
		else
			priv_run cp "$_tmp" "$_file" || { rm -f "$_tmp"; return 1; }
			priv_run chmod 600 "$_file" || true
			rm -f "$_tmp"
		fi
	else
		echo "REMOTE: Keine Duplikate in $_file (Zeilen=$_before)"
		rm -f "$_tmp"
	fi
}

key_vorhanden() {
	_file="$1"
	_line=""
	_id=""
	[ -f "$_file" ] || return 1
	while IFS= read -r _line || [ -n "$_line" ]; do
		case "$_line" in
			""|\#*) continue ;;
		esac
		_id="$(key_id_of_line "$_line")"
		if [ "$_id" = "$PUBKEY_ID" ]; then
			return 0
		fi
	done < "$_file"
	if [ -n "$PUBKEY" ] && grep -Fq "$PUBKEY" "$_file" 2>/dev/null; then
		return 0
	fi
	if [ -n "$MARKER" ] && grep -Fq "$MARKER" "$_file" 2>/dev/null; then
		return 0
	fi
	return 1
}

ensure_file() {
	# Legacy-Name: nur .ssh + authorized_keys, NIEMALS Home (/root, /home/x) anlegen
	_file="$1"
	_owner="$2"
	_ssh_dir="$(dirname "$_file")"
	_home="$(dirname "$_ssh_dir")"

	# Root immer fest /root (nie relativ aus kaputtem getent-Home)
	if [ "$_owner" = "root" ] || [ "$_file" = "/root/.ssh/authorized_keys" ]; then
		_home="/root"
		_ssh_dir="/root/.ssh"
		_file="/root/.ssh/authorized_keys"
	fi

	# Absolute Pfade erzwingen – verhindert z.B. ./Dummy/.ssh im CWD
	case "$_home" in
		/*) ;;
		*)
			echo "REMOTE FEHLER: Home nicht absolut ('$_home') – Abbruch (kein Dummy-Anlegen)" >&2
			return 1
			;;
	esac
	case "$_file" in
		/*) ;;
		*)
			echo "REMOTE FEHLER: Auth-Pfad nicht absolut ('$_file') – Abbruch" >&2
			return 1
			;;
	esac

	echo "REMOTE: 1) Home pruefen (nicht anlegen): $_home"
	if [ -d "$_home" ]; then
		echo "REMOTE: Home vorhanden: $_home"
	elif priv_run test -d "$_home"; then
		echo "REMOTE: Home vorhanden (via sudo/su): $_home"
	else
		echo "REMOTE FEHLER: Home fehlt: $_home - wird nicht angelegt" >&2
		return 1
	fi

	echo "REMOTE: 2) Verzeichnis .ssh pruefen/anlegen: $_ssh_dir"
	if [ -d "$_ssh_dir" ]; then
		echo "REMOTE: .ssh vorhanden"
	elif priv_run test -d "$_ssh_dir"; then
		echo "REMOTE: .ssh vorhanden (via sudo/su)"
	else
		echo "REMOTE: lege nur .ssh an (Home bleibt unangetastet)"
		# Kein mkdir -p auf Home-Pfad als Normaluser (wuerde /root anlegen wollen)
		if [ "$(id -un 2>/dev/null)" = "root" ] || [ "$(id -u 2>/dev/null)" = "0" ]; then
			mkdir -m 700 "$_ssh_dir" || return 1
		else
			priv_run mkdir -m 700 "$_ssh_dir" || {
				echo "REMOTE FEHLER: .ssh nicht anlegbar: $_ssh_dir" >&2
				return 1
			}
		fi
		if [ -n "$_owner" ] && [ "$_owner" != "DROPBEAR" ]; then
			priv_run chown "${_owner}:${_owner}" "$_ssh_dir" || true
		fi
		priv_run chmod 700 "$_ssh_dir" || chmod 700 "$_ssh_dir" 2>/dev/null || true
	fi

	echo "REMOTE: 3) Datei authorized_keys pruefen/anlegen: $_file"
	if [ -f "$_file" ]; then
		echo "REMOTE: authorized_keys vorhanden"
	elif priv_run test -f "$_file"; then
		echo "REMOTE: authorized_keys vorhanden (via sudo/su)"
	else
		echo "REMOTE: lege authorized_keys an"
		if touch "$_file" 2>/dev/null; then
			:
		else
			priv_run touch "$_file" || {
				echo "REMOTE FEHLER: authorized_keys nicht anlegbar: $_file" >&2
				return 1
			}
		fi
		if [ -n "$_owner" ] && [ "$_owner" != "DROPBEAR" ]; then
			priv_run chown "${_owner}:${_owner}" "$_file" || true
		fi
		priv_run chmod 600 "$_file" || chmod 600 "$_file" 2>/dev/null || true
	fi
	return 0
}

append_key() {
	_file="$1"
	_owner="$2"
	_old="$(stat -c '%a' "$_file" 2>/dev/null || echo 600)"
	_tmpkey=""
	echo "REMOTE: 4) temporaere Schreibrechte / Key schreiben: $_file"
	# Temp. Schreibrecht setzen, danach wieder 600
	if [ -w "$_file" ]; then
		:
	elif chmod u+w "$_file" 2>/dev/null; then
		echo "REMOTE: chmod u+w gesetzt (war $_old)"
	else
		echo "REMOTE: setze Schreibrecht via sudo/su"
		priv_run chmod 666 "$_file" || priv_run chmod 600 "$_file" || true
	fi

	if [ -w "$_file" ]; then
		printf '%s\n' "$PUBKEY" >> "$_file"
		echo "REMOTE: Key angehaengt (direkt)"
	else
		_tmpkey="$(mktemp 2>/dev/null || echo /tmp/pk.$$)"
		printf '%s\n' "$PUBKEY" > "$_tmpkey"
		chmod 600 "$_tmpkey" 2>/dev/null || true
		if ! priv_run sh -c "cat '$_tmpkey' >> '$_file'"; then
			rm -f "$_tmpkey"
			echo "REMOTE FEHLER: Anhaengen an $_file fehlgeschlagen (sudo/su?)" >&2
			return 1
		fi
		rm -f "$_tmpkey"
		echo "REMOTE: Key angehaengt (sudo/su)"
	fi

	# Rechte wieder einschraenken
	chmod 600 "$_file" 2>/dev/null || priv_run chmod 600 "$_file" || true
	if [ -n "$_owner" ] && [ "$_owner" != "DROPBEAR" ]; then
		priv_run chown "${_owner}:${_owner}" "$_file" || true
	fi
	return 0
}

process_auth_file() {
	_file="$1"
	_owner="$2"
	echo "REMOTE: ==== bearbeite $_file (owner=$_owner) ===="
	ensure_file "$_file" "$_owner" || return 1
	echo "REMOTE: 5) Duplikate pruefen/entfernen"
	dedupe_auth_file "$_file" || true
	echo "REMOTE: 6) Ziel-Key pruefen"
	if key_vorhanden "$_file"; then
		echo "REMOTE: Key bereits vorhanden - kein erneutes Einfuegen"
		dedupe_auth_file "$_file" || true
		return 0
	fi
	echo "REMOTE: 7) Key hinzufuegen"
	append_key "$_file" "$_owner" || return 1
	dedupe_auth_file "$_file" || true
	if key_vorhanden "$_file"; then
		echo "REMOTE: Key erfolgreich eingetragen in $_file"
		return 0
	fi
	echo "REMOTE FEHLER: Key nach Schreiben nicht in $_file gefunden" >&2
	return 1
}

if [ "$TARGET" = "DROPBEAR" ]; then
	process_auth_file "$DROPBEAR_AUTH" "DROPBEAR"
	exit $?
fi

TARGET="$(printf '%s' "$TARGET" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [ "$TARGET" = "root" ]; then
	REMOTE_HOME="/root"
	AUTH_FILE="/root/.ssh/authorized_keys"
	echo "REMOTE: Home=$REMOTE_HOME Auth=$AUTH_FILE"
	# Login als pi/User: gesamter Root-Pfad nur via sudo/su (sonst Datei unlesbar)
	if ! is_uid0; then
		process_root_via_priv
		exit $?
	fi
	process_auth_file "$AUTH_FILE" "root"
	exit $?
fi

# Kein Passwd-User (z.B. Waisen-Ordner /home/dummy) – nicht anlegen, nur ueberspringen
user_exists=0
if command -v getent >/dev/null 2>&1; then
	getent passwd "$TARGET" >/dev/null 2>&1 && user_exists=1
elif [ -f /etc/passwd ]; then
	awk -F: -v u="$TARGET" '$1==u {f=1} END{exit !f}' /etc/passwd && user_exists=1
else
	id "$TARGET" >/dev/null 2>&1 && user_exists=1
fi
if [ "$user_exists" != "1" ]; then
	echo "REMOTE: User '$TARGET' existiert nicht in Passwd – ueberspringe (kein Anlegen)"
	exit 0
fi

REMOTE_HOME="$(home_of "$TARGET")"
case "$REMOTE_HOME" in
	/home/root|/home/root/) REMOTE_HOME="/root" ;;
	/*) ;;
	*)
		echo "REMOTE FEHLER: Home fuer '$TARGET' nicht absolut ('$REMOTE_HOME') – ueberspringe" >&2
		exit 12
		;;
esac
AUTH_FILE="${REMOTE_HOME}/.ssh/authorized_keys"
echo "REMOTE: Home=$REMOTE_HOME Auth=$AUTH_FILE"
process_auth_file "$AUTH_FILE" "$TARGET"
exit $?
EOF
}

ensure_key_fuer_ziel() {
	#
	# Beschreibung: Dedupliziert und stellt Pubkey fuer User oder DROPBEAR sicher.
	# Parameter: $1 = Benutzername oder DROPBEAR
	# Rueckgabewert: 0 bei Erfolg
	# Fehlerfaelle: Remote fehlgeschlagen
	# Beispiel: ensure_key_fuer_ziel root
	#
	local ziel="$1"
	local rc=0
	schritt_meldung "Bearbeite Ziel: $ziel (SSH-Login: $login_account)"
	log_nachricht "START ensure_key ziel=$ziel login=$login_account host=$ziel_host"
	# shellcheck disable=SC2029
	set +e
	remote_skript_ensure_key | ssh_remote \
		PUBKEY_B64="$(pubkey_b64)" \
		MARKER="$schluessel_marker" \
		HAS_SUDO="$(has_sudo_flag)" \
		SUDO_PASS="$login_password" \
		DROPBEAR_AUTH_PATH="$DROPBEAR_AUTH" \
		sh -s -- "$ziel"
	rc=$?
	set -e
	# Pipeline ohne pipefail: Exit von ssh zählt; 0 trotzdem prüfen über rc
	if [ "$rc" -eq 0 ]; then
		info_meldung "Ziel OK: $ziel"
		log_nachricht "OK ensure_key ziel=$ziel"
		return 0
	fi
	fehler_melden "Ziel fehlgeschlagen: $ziel (Exit=$rc)"
	log_nachricht "FAIL ensure_key ziel=$ziel rc=$rc"
	return 1
}

liste_bekannte_benutzer() {
	#
	# Beschreibung: Listet remote echte Login-User (root + Passwd UID>=1000).
	#   /home/* nur wenn dazu ein Passwd-Konto existiert (kein Waisen-Ordner).
	# Parameter: keine
	# Rueckgabewert: Benutzernamen zeilenweise
	# Fehlerfaelle: leere Liste
	# Beispiel: liste_bekannte_benutzer
	#
	schritt_meldung "Ermittle bekannte Benutzer auf dem Zielsystem ..."
	# shellcheck disable=SC2029
	ssh_remote sh -s <<'EOF' 2>/dev/null || true
set +e
echo root
# Nur echte Passwd-Accounts (UID>=1000), keine Waisen unter /home
if command -v getent >/dev/null 2>&1; then
	getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $1 != "root" && $1 != "" { print $1 }'
elif [ -f /etc/passwd ]; then
	awk -F: '$3 >= 1000 && $3 < 65534 && $1 != "root" && $1 != "" { print $1 }' /etc/passwd
fi
if [ -d /home ]; then
	for d in /home/*; do
		[ -d "$d" ] || continue
		b="$(basename "$d")"
		[ "$b" = "root" ] && continue
		[ "$b" = "*" ] && continue
		[ -z "$b" ] && continue
		# Ordner ohne Passwd-User (z.B. /home/dummy) ignorieren
		if command -v getent >/dev/null 2>&1; then
			getent passwd "$b" >/dev/null 2>&1 || continue
		elif [ -f /etc/passwd ]; then
			awk -F: -v u="$b" '$1==u {f=1} END{exit !f}' /etc/passwd || continue
		else
			id "$b" >/dev/null 2>&1 || continue
		fi
		printf '%s\n' "$b"
	done
fi
EOF
}

entferne_duplikate_liste() {
	#
	# Beschreibung: Entfernt doppelte Zeilen, behaelt Reihenfolge.
	# Parameter: stdin
	# Rueckgabewert: eindeutige Zeilen
	# Fehlerfaelle: keine
	# Beispiel: echo a | entferne_duplikate_liste
	#
	awk 'NF && !seen[$0]++'
}

erkenne_dropbear() {
	#
	# Beschreibung: Setzt ist_router, wenn Dropbear/OpenWrt erkannt wird.
	# Parameter: keine
	# Rueckgabewert: 0 wenn erkannt, 1 sonst
	# Fehlerfaelle: SSH-Fehler
	# Beispiel: erkenne_dropbear && echo ja
	#
	schritt_meldung "Pruefe auf Router/Dropbear ($DROPBEAR_AUTH) ..."
	# shellcheck disable=SC2029
	if ssh_remote sh -s <<EOF
set +e
if [ -d /etc/dropbear ] || [ -f $DROPBEAR_AUTH ] || [ -f /etc/openwrt_release ]; then
	echo DROPBEAR_YES
	exit 0
fi
echo DROPBEAR_NO
exit 1
EOF
	then
		ist_router=true
		info_meldung "Router/Dropbear erkannt."
		log_nachricht "ROUTER/DROPBEAR erkannt host=$ziel_host"
		return 0
	fi
	ist_router=false
	debug_meldung "Kein Dropbear-/OpenWrt-Hinweis gefunden."
	log_nachricht "Kein Dropbear auf $ziel_host"
	return 1
}

pruefe_dropbear_router() {
	#
	# Beschreibung: Erkennt Router/Dropbear und pflegt authorized_keys dort.
	# Parameter: keine
	# Rueckgabewert: 0 OK; 1 bei Schreibfehler
	# Fehlerfaelle: Dropbear-Schreiben fehlgeschlagen
	# Beispiel: pruefe_dropbear_router
	#
	erkenne_dropbear || return 0
	ensure_key_fuer_ziel DROPBEAR || return 1
	return 0
}

remote_skript_remove_key() {
	#
	# Beschreibung: Remote-Skript (POSIX sh): Marker-Zeilen entfernen.
	# Parameter: keine
	# Rueckgabewert: Skripttext
	# Fehlerfaelle: keine
	# Beispiel: remote_skript_remove_key
	#
	cat <<'EOF'
# POSIX sh - kein [[ ]]
set -e
TARGET="$1"
DROPBEAR_AUTH="${DROPBEAR_AUTH_PATH:-/etc/dropbear/authorized_keys}"
echo "REMOTE: Remove Marker='$MARKER' Ziel='$TARGET'"

priv_run() {
	if "$@" ; then return 0; fi
	if [ "$HAS_SUDO" = "1" ] && command -v sudo >/dev/null 2>&1; then
		printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@" && return 0
	fi
	if [ "$HAS_SUDO" = "1" ] && command -v su >/dev/null 2>&1; then
		_cmd="$*"
		printf '%s\n' "$SUDO_PASS" | su - root -c "$_cmd" && return 0
	fi
	return 1
}

home_of() {
	u="$(printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	if [ "$u" = "root" ]; then
		printf '/root\n'
		return 0
	fi
	h=""
	if command -v getent >/dev/null 2>&1; then
		h="$(getent passwd "$u" | cut -d: -f6 || true)"
		h="$(printf '%s' "$h" | tr -d '\r\n')"
	fi
	if [ "$h" = "/home/root" ] || [ "$h" = "/home/root/" ]; then
		h="/root"
	fi
	case "$h" in
		""|.*) h="" ;;
		/*) ;;
		*) h="" ;;
	esac
	if [ -n "$h" ]; then printf '%s\n' "$h"
	else printf '/home/%s\n' "$u"; fi
}

remove_from_file() {
	file="$1"
	tmp=""
	[ -f "$file" ] || { echo "REMOTE: Datei fehlt $file"; return 0; }
	if ! grep -Fq "$MARKER" "$file" 2>/dev/null; then
		echo "REMOTE: Marker nicht in $file"
		return 0
	fi
	tmp="$(mktemp 2>/dev/null || echo /tmp/rm.$$)"
	grep -Fv "$MARKER" "$file" > "$tmp" || true
	if mv "$tmp" "$file" 2>/dev/null; then
		chmod 600 "$file" 2>/dev/null || true
	else
		priv_run cp "$tmp" "$file" || { rm -f "$tmp"; return 1; }
		priv_run chmod 600 "$file" || true
		rm -f "$tmp"
	fi
	echo "REMOTE: Marker entfernt aus $file"
}

if [ "$TARGET" = "DROPBEAR" ]; then
	remove_from_file "$DROPBEAR_AUTH"
	exit $?
fi
if [ "$TARGET" = "root" ]; then
	remove_from_file "/root/.ssh/authorized_keys"
	exit $?
fi
# Kein Passwd-User (Waisen-Ordner) – ueberspringen
if command -v getent >/dev/null 2>&1; then
	getent passwd "$TARGET" >/dev/null 2>&1 || { echo "REMOTE: User '$TARGET' fehlt – ueberspringe"; exit 0; }
elif ! id "$TARGET" >/dev/null 2>&1; then
	echo "REMOTE: User '$TARGET' fehlt – ueberspringe"
	exit 0
fi
remove_from_file "$(home_of "$TARGET")/.ssh/authorized_keys"
exit $?
EOF
}

remove_key_fuer_ziel() {
	#
	# Beschreibung: Entfernt Marker fuer User oder DROPBEAR.
	# Parameter: $1 = Ziel
	# Rueckgabewert: 0 bei Erfolg
	# Fehlerfaelle: Remote fehlgeschlagen
	# Beispiel: remove_key_fuer_ziel root
	#
	local ziel="$1"
	schritt_meldung "Entferne Marker fuer: $ziel"
	# shellcheck disable=SC2029
	remote_skript_remove_key | ssh_remote \
		MARKER="$schluessel_marker" \
		HAS_SUDO="$(has_sudo_flag)" \
		SUDO_PASS="$login_password" \
		DROPBEAR_AUTH_PATH="$DROPBEAR_AUTH" \
		sh -s -- "$ziel" || return 1
	return 0
}

orchestriere_add() {
	#
	# Beschreibung: Root-First, Deduplizierung, User, Dropbear.
	# Parameter: keine
	# Rueckgabewert: keines; Exit bei kritischem Fehler
	# Fehlerfaelle: weder Root noch -U erreichbar
	# Beispiel: orchestriere_add
	#
	local user_list="" u
	local fehler=0

	schritt_meldung "=== Start Key-Verteilung auf $ziel_host ==="
	log_nachricht "ORCHESTRIERUNG ADD host=$ziel_host user_param=$remote_user"

	if teste_login_als root; then
		root_zugang=true
		setze_ssh_ziel root
	else
		root_zugang=false
	fi

	if [[ "$root_zugang" == true ]]; then
		info_meldung "Pfad: direkter Root-Zugang – pruefe /root/.ssh/authorized_keys"
		ensure_key_fuer_ziel root || fehler=1
		user_list="$(liste_bekannte_benutzer | entferne_duplikate_liste | grep -vx root || true)"
		debug_meldung "Weitere Benutzer: $(echo "$user_list" | tr '\n' ' ')"
		while IFS= read -r u; do
			[[ -n "$u" ]] || continue
			# Nur gueltige Unix-Usernamen; keine Artefakte/SSH-Muell
			[[ "$u" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || {
				warnung_melden "Ignoriere ungueltigen Listeneintrag: '$u'"
				continue
			}
			ensure_key_fuer_ziel "$u" || {
				warnung_melden "Benutzer $u fehlgeschlagen/uebersprungen."
				fehler=1
			}
		done <<< "$user_list"
		pruefe_dropbear_router || fehler=1
	else
		if [[ "$remote_user" == "root" ]]; then
			beende_mit_fehler 9 "Kein Root-Zugang. Bitte -U <user> und ggf. -P/-ppk angeben."
		fi
		info_meldung "Pfad: Benutzerzugang '$remote_user' (Root per sudo/su → /root)"
		if ! teste_login_als "$remote_user"; then
			beende_mit_fehler 9 "Weder Root noch $remote_user erreichbar (Auth pruefen)."
		fi
		setze_ssh_ziel "$remote_user"
		ensure_key_fuer_ziel "$remote_user" || fehler=1
		schritt_meldung "Root-authorized_keys (/root/.ssh) ueber sudo/su bearbeiten ..."
		# sudo/su braucht Passwort – bei PPK-Login ggf. noch nicht gesetzt
		stelle_login_passwort_sicher "sudo/su ${remote_user}@${ziel_host}"
		if ! ensure_key_fuer_ziel root; then
			fehler_melden "Root-Eintrag via sudo/su fehlgeschlagen."
			fehler=1
		fi
		pruefe_dropbear_router || fehler=1
	fi

	if [[ "$fehler" -ne 0 ]]; then
		beende_mit_fehler 6 "Mindestens ein Schritt fehlgeschlagen (siehe Log/Konsole)."
	fi
	schritt_meldung "=== Key-Verteilung abgeschlossen ==="
}

orchestriere_remove() {
	#
	# Beschreibung: Entfernt Marker bei Root/User und Dropbear.
	# Parameter: keine
	# Rueckgabewert: keines
	# Fehlerfaelle: kein Zugang
	# Beispiel: orchestriere_remove
	#
	local user_list="" u
	schritt_meldung "=== Start Key-Entfernung (Marker=$schluessel_marker) ==="

	if teste_login_als root; then
		setze_ssh_ziel root
		remove_key_fuer_ziel root || true
		user_list="$(liste_bekannte_benutzer | entferne_duplikate_liste | grep -vx root || true)"
		while IFS= read -r u; do
			[[ -n "$u" ]] || continue
			[[ "$u" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || continue
			remove_key_fuer_ziel "$u" || true
		done <<< "$user_list"
		erkenne_dropbear && remove_key_fuer_ziel DROPBEAR || true
		return 0
	fi

	if [[ "$remote_user" == "root" ]]; then
		beende_mit_fehler 9 "Kein Root-Zugang. Bitte -U <user> angeben."
	fi
	teste_login_als "$remote_user" || beende_mit_fehler 9 "Login als $remote_user fehlgeschlagen."
	setze_ssh_ziel "$remote_user"
	remove_key_fuer_ziel "$remote_user" || true
	stelle_login_passwort_sicher "sudo/su ${remote_user}@${ziel_host}"
	remove_key_fuer_ziel root || true
	erkenne_dropbear && remove_key_fuer_ziel DROPBEAR || true
}

parse_argumente() {
	#
	# Beschreibung: Parst CLI inkl. -U/-P/-ppk und Style-Guide-Flags.
	# Parameter: CLI-Argumente
	# Rueckgabewert: setzt Globals; Exit bei Hilfe/Version
	# Fehlerfaelle: unbekannte Optionen
	# Beispiel: parse_argumente "$@"
	#
	local zeige_hilfe_flag=false
	local zeige_version_flag=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
			-h|--help) zeige_hilfe_flag=true; shift ;;
			--version) zeige_version_flag=true; shift ;;
			--log) logging_aktiv=true; shift ;;
			-E|--Ende) warte_am_ende=true; shift ;;
			-4) ip_familie="-4"; shift ;;
			-6) ip_familie="-6"; shift ;;
			-A) aktion="add"; shift ;;
			-R) aktion="remove"; shift ;;
			-U)
				[[ -n "${2:-}" ]] || beende_mit_fehler 1 "-U erwartet einen Benutzernamen."
				remote_user="$2"
				shift 2
				;;
			-P)
				[[ $# -ge 2 ]] || beende_mit_fehler 1 "-P erwartet Passwort oder Passphrase."
				printf -v login_password '%s' "$2"
				[[ -n "$login_password" ]] || beende_mit_fehler 1 "-P: Passwort darf nicht leer sein."
				shift 2
				;;
			-P=*)
				printf -v login_password '%s' "${1#-P=}"
				[[ -n "$login_password" ]] || beende_mit_fehler 1 "-P: Passwort darf nicht leer sein."
				shift
				;;
			-ppk|--ppk)
				[[ -n "${2:-}" ]] || beende_mit_fehler 1 "-ppk erwartet eine Datei.ppk."
				ppk_datei="$2"
				shift 2
				;;
			--key-file)
				[[ -n "${2:-}" ]] || beende_mit_fehler 1 "--key-file erwartet einen Pfad."
				key_datei="$2"
				shift 2
				;;
			--marker)
				[[ -n "${2:-}" ]] || beende_mit_fehler 1 "--marker erwartet einen Text."
				schluessel_marker="$2"
				shift 2
				;;
			-*)
				fehler_melden "Ungueltiger Parameter: $1"
				zeige_hilfe
				exit 1
				;;
			*)
				if [[ -z "$ziel_host" ]]; then
					ziel_host="$1"
					shift
				else
					fehler_melden "Unerwartetes Argument: $1"
					zeige_hilfe
					exit 1
				fi
				;;
		esac
	done

	if [[ "$zeige_version_flag" == true ]]; then
		zeige_version
		warte_auf_programmende
		exit 0
	fi
	if [[ "$zeige_hilfe_flag" == true ]]; then
		zeige_hilfe
		warte_auf_programmende
		exit 0
	fi
}

main() {
	#
	# Beschreibung: Orchestriert Auth und Key-Verteilung mit Deduplizierung.
	# Parameter: CLI-Argumente
	# Rueckgabewert: Exit-Code 0 bei Erfolg
	# Fehlerfaelle: siehe beende_mit_fehler
	# Beispiel: main "$@"
	#
	trap aufraeumen_beim_exit EXIT
	parse_argumente "$@"

	if [[ "$logging_aktiv" == true ]]; then
		: > "$LOGDATEI"
		log_nachricht "===== $SKRIPTNAME $VERSION gestartet ====="
		log_nachricht "Host=$ziel_host UserParam=$remote_user Aktion=$aktion KeyFile=$key_datei"
	fi

	info_meldung "Version $VERSION – Host=$ziel_host Aktion=$aktion"
	command -v ssh >/dev/null 2>&1 || beende_mit_fehler 4 "ssh ist nicht installiert."
	baue_ssh_optionen

	if [[ "$aktion" == "remove" ]]; then
		orchestriere_remove
	else
		lade_pubkey
		orchestriere_add
	fi
	info_meldung "Fertig."
	log_nachricht "===== $SKRIPTNAME beendet (OK) router=$ist_router ====="
}

main "$@"
