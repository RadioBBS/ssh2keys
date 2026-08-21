"""
ssh2keys – Unit-Tests fuer CLI und Dateikopf (ohne Remote-Hosts).

Projekt:     ssh2keys
Modul:       tests/test_ssh2keys.py
Version:     1.7.0
Stand:       2026-08-21
Abhaengig:   Bash >= 4; OpenSSH (ssh); sshpass (Passwort-Login); optional putty-tools/puttygen (-ppk)
Bezug:       requirements.txt (leer – keine Python-Pakete)
Lizenz:      MIT
Upstream:    –
Erstellt mit: Cursor Grok 4.6
Autor:       (FFHB) / RadioBBS

Beschreibung
------------
Prueft Syntax, --help/--version und einheitliche Metadaten. Kein SSH,
keine echten Zielsysteme.

Historie
--------
Version 1.7.0 – 2026-08-21 – CLI- und Kopfpruefung ohne Netz

Aufruf / Nutzung
----------------
  python -m unittest tests.test_ssh2keys
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "ssh2keys.sh"
EXPECTED_VERSION = "1.7.0"
EXPECTED_STAND = "2026-08-21"
PFLICHTFELDER = (
    "Projekt:",
    "Modul:",
    "Version:",
    "Stand:",
    "Abhaengig:",
    "Bezug:",
    "Lizenz:",
    "Upstream:",
    "Erstellt mit:",
    "Autor:",
)


def finde_bash() -> str:
    """
    Beschreibung: Sucht eine Bash, bevorzugt Git-Bash unter Windows.
    Parameter: keine
    Rueckgabewert: Pfad zur bash-Executable
    Fehlerfaelle: FileNotFoundError, wenn keine Bash vorhanden ist
    Beispiel: finde_bash()
    """
    program_files = os.environ.get("PROGRAMFILES", r"C:\Program Files")
    kandidaten = [
        Path(program_files) / "Git" / "bin" / "bash.exe",
        Path(program_files) / "Git" / "usr" / "bin" / "bash.exe",
    ]
    for pfad in kandidaten:
        if pfad.is_file():
            return str(pfad)
    gefunden = shutil.which("bash")
    if gefunden:
        return gefunden
    raise FileNotFoundError("bash nicht gefunden (Git-Bash oder WSL).")


def lese_skripttext() -> str:
    """
    Beschreibung: Liest ssh2keys.sh als UTF-8.
    Parameter: keine
    Rueckgabewert: Dateiinhalt
    Fehlerfaelle: FileNotFoundError / UnicodeError
    Beispiel: "VERSION=" in lese_skripttext()
    """
    return SCRIPT.read_text(encoding="utf-8")


class TestSsh2keysDateien(unittest.TestCase):
    """Prueft Pflichtartefakte und einheitliche Versionsfelder."""

    def test_pflichtartefakte_vorhanden(self) -> None:
        """
        Beschreibung: README, LICENSE, CHANGELOG, requirements, gitignore.
        Parameter: keine
        Rueckgabewert: keines (Assertion)
        Fehlerfaelle: AssertionError bei fehlender Datei
        Beispiel: TestSsh2keysDateien().test_pflichtartefakte_vorhanden()
        """
        for name in (
            "ssh2keys.sh",
            "README.md",
            "LICENSE",
            "CHANGELOG.md",
            "requirements.txt",
            ".gitignore",
            "PROJECT.yaml",
        ):
            self.assertTrue((ROOT / name).is_file(), f"fehlt: {name}")

    def test_skriptkopf_pflichtfelder(self) -> None:
        """
        Beschreibung: Dateikopf enthaelt alle Styleguide-Pflichtfelder.
        Parameter: keine
        Rueckgabewert: keines (Assertion)
        Fehlerfaelle: AssertionError
        Beispiel: TestSsh2keysDateien().test_skriptkopf_pflichtfelder()
        """
        text = lese_skripttext()
        for feld in PFLICHTFELDER:
            with self.subTest(feld=feld):
                self.assertIn(feld, text)

    def test_version_und_stand_im_skript(self) -> None:
        """
        Beschreibung: VERSION/Stand im Skript entsprechen diesem Release.
        Parameter: keine
        Rueckgabewert: keines (Assertion)
        Fehlerfaelle: AssertionError
        Beispiel: TestSsh2keysDateien().test_version_und_stand_im_skript()
        """
        text = lese_skripttext()
        version = re.search(r'^VERSION="([^"]+)"', text, re.M)
        stand = re.search(r'^VERSION_DATUM="([^"]+)"', text, re.M)
        self.assertIsNotNone(version)
        self.assertIsNotNone(stand)
        self.assertEqual(version.group(1), EXPECTED_VERSION)
        self.assertEqual(stand.group(1), EXPECTED_STAND)
        self.assertIn("Autor:       (FFHB) / RadioBBS", text)
        self.assertNotIn("\r", text)

    def test_readme_version(self) -> None:
        """
        Beschreibung: README traegt dieselbe Version und dasselbe Datum.
        Parameter: keine
        Rueckgabewert: keines (Assertion)
        Fehlerfaelle: AssertionError
        Beispiel: TestSsh2keysDateien().test_readme_version()
        """
        text = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn(f"Version:     {EXPECTED_VERSION}", text)
        self.assertIn(f"Stand:       {EXPECTED_STAND}", text)


class TestSsh2keysCli(unittest.TestCase):
    """Prueft bash -n, --help und --version ohne Netzverbindung."""

    @classmethod
    def setUpClass(cls) -> None:
        """
        Beschreibung: Ermittelt Bash oder ueberspringt die CLI-Tests.
        Parameter: keine
        Rueckgabewert: keines
        Fehlerfaelle: SkipTest ohne Bash
        Beispiel: TestSsh2keysCli.setUpClass()
        """
        try:
            cls.bash = finde_bash()
        except FileNotFoundError as exc:
            raise unittest.SkipTest(str(exc)) from exc

    def _run(self, *args: str) -> subprocess.CompletedProcess[str]:
        """
        Beschreibung: Startet ssh2keys.sh mit Git-/System-Bash.
        Parameter: args – CLI-Argumente nach dem Skriptnamen
        Rueckgabewert: CompletedProcess mit Text-Ausgabe
        Fehlerfaelle: subprocess.SubprocessError
        Beispiel: self._run("--version")
        """
        return subprocess.run(
            [self.bash, str(SCRIPT), *args],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )

    def test_bash_syntax(self) -> None:
        """
        Beschreibung: bash -n findet keine Syntaxfehler.
        Parameter: keine
        Rueckgabewert: keines (Assertion)
        Fehlerfaelle: AssertionError
        Beispiel: TestSsh2keysCli().test_bash_syntax()
        """
        result = subprocess.run(
            [self.bash, "-n", str(SCRIPT)],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_help(self) -> None:
        """
        Beschreibung: --help nennt Version, Parameter und Beispiele.
        Parameter: keine
        Rueckgabewert: keines (Assertion)
        Fehlerfaelle: AssertionError
        Beispiel: TestSsh2keysCli().test_help()
        """
        result = self._run("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        ausgabe = result.stdout
        self.assertIn(EXPECTED_VERSION, ausgabe)
        self.assertIn("--key-file", ausgabe)
        self.assertIn("-E, --Ende", ausgabe)
        self.assertIn("Beispiele:", ausgabe)

    def test_version(self) -> None:
        """
        Beschreibung: --version nennt Nummer, Datum und Beschreibung.
        Parameter: keine
        Rueckgabewert: keines (Assertion)
        Fehlerfaelle: AssertionError
        Beispiel: TestSsh2keysCli().test_version()
        """
        result = self._run("--version")
        self.assertEqual(result.returncode, 0, result.stderr)
        ausgabe = result.stdout
        self.assertIn(EXPECTED_VERSION, ausgabe)
        self.assertIn(EXPECTED_STAND, ausgabe)
        self.assertIn("SSH-Pubkey", ausgabe)

    def test_ungueltiger_parameter(self) -> None:
        """
        Beschreibung: Unbekannte Option endet mit Fehler und Hilfe.
        Parameter: keine
        Rueckgabewert: keines (Assertion)
        Fehlerfaelle: AssertionError
        Beispiel: TestSsh2keysCli().test_ungueltiger_parameter()
        """
        result = self._run("--gibt-es-nicht")
        self.assertNotEqual(result.returncode, 0)
        text = result.stdout + result.stderr
        self.assertIn("Ungueltiger Parameter", text)


if __name__ == "__main__":
    unittest.main()
