# Prüfauftrag & Anforderungsbericht – RAM-Monitor

> **An Cursor:** Dieses Dokument beschreibt Zweck, Soll-Funktionen und
> Ist-Zustand des RAM-Monitors. Bitte prüfe die Skripte gegen diese
> Anforderungen, finde Fehler und Lücken, und **ergänze am Ende deinen Input**
> (fehlende Features, Verbesserungen, Risiken). Der konkrete Fragenkatalog
> steht unter [Prüfauftrag](#5-prüfauftrag-an-cursor).

Betroffene Dateien im Ordner `RamMonitor/`:

| Datei | Rolle |
|---|---|
| `Track-Memory.ps1` | Messung (Logger) → schreibt CSV |
| `Analyze-Memory.ps1` | Auswertung → Empfehlung + HTML-Bericht |
| `Messung-starten.cmd` | Doppelklick-Starter für die Messung |
| `Auswertung-starten.cmd` | Doppelklick-Starter für die Auswertung |
| `README.md` | Anwender-Anleitung (Deutsch) |

---

## 1. Kontext & Ziel

Ein Elektroplanungsunternehmen beschafft neue Arbeitsplatz-PCs. Ein Testgerät
hat **64 GB RAM**. Da RAM teurer / schwerer zu beschaffen wird, soll anhand des
Testgeräts belegt werden, ob **32 GB oder sogar 16 GB** für den Arbeitsalltag
ausreichen.

Typische Last: CAD (**Trimble Nova**, **Tinline Schema**), Office, Video­konferenz,
IP-Telefonie, Browser – oft mehreres gleichzeitig.

**Geschäftsziel:** eine belastbare, nachvollziehbare Datengrundlage für die
Beschaffungsentscheidung – kein Bauchgefühl.

### Fachliche Kernannahme (bitte prüfen!)

Maßgeblich ist der **zugesicherte Speicher (Commit Charge)**, nicht die
„belegt"-Anzeige. Begründung: Windows nutzt freien RAM als Datei-Cache, daher
ist „belegt" auf einem 64-GB-Gerät künstlich hoch. Commit Charge = tatsächlich
angeforderter Speicher, unabhängig vom verbauten RAM → richtige Basis für die
Dimensionierung. **Cursor: ist diese Annahme methodisch korrekt? Gegenargumente?**

---

## 2. Soll-Funktionen (Anforderungen)

### Messung (`Track-Memory.ps1`)

- [ ] **F1** Läuft ohne Installation und **ohne Adminrechte** (nur PowerShell).
- [ ] **F2** Misst in festem Intervall (Standard 60 s, parametrierbar).
- [ ] **F3** Erfasst **systemweit**: Commit Charge, Commit-Grenze, Commit-%,
      physisch belegt/frei, verfügbar, Cache, Auslagerung (harte Seitenfehler).
- [ ] **F4** Erfasst **pro Programm**: Working Set und privaten Speicher,
      zusammengefasst je Programmname (Top-N einzeln + „(sonstige)").
- [ ] **F5** Schreibt **sofort** je Messpunkt in CSV (kein Datenverlust bei
      Absturz/Ausschalten).
- [ ] **F6** **Locale-robust**: funktioniert auf deutschem *und* englischem
      Windows (keine lokalisierten Performance-Counter-Namen).
- [ ] **F7** Läuft unbegrenzt bis STRG+C **oder** für eine parametrierbare
      Dauer.
- [ ] **F8** Dateinamen enthalten Rechnername + Startzeit (mehrere Läufe /
      mehrere PCs kollidieren nicht).
- [ ] **F9** Live-Statuszeile; Auslagerung wird optisch hervorgehoben.
- [ ] **F10** **Datenschutz:** nur Zahlen + Programmnamen, keine Fenstertitel,
      Dateipfade oder Inhalte.

### Auswertung (`Analyze-Memory.ps1`)

- [ ] **F11** Findet automatisch die neueste Messung oder nimmt angegebene
      Dateien.
- [ ] **F12** Bildet Kennzahlen des Commit Charge: **Max, p99, p95, Median,
      Mittelwert**.
- [ ] **F13** Leitet eine **RAM-Empfehlung (16/32/64 GB)** ab (80-%-Reserve-Regel),
      getrennt nach Dauerbedarf (p99) und Spitze (Max).
- [ ] **F14** Prüft **Auslagerung** und warnt, falls schon auf 64 GB
      Speicherdruck bestand.
- [ ] **F15** Tabelle der **größten Speicherverbraucher** je Programm.
- [ ] **F16** Erzeugt einen **HTML-Bericht** (light/dark) zum Weiterleiten.
- [ ] **F17** Zahlen-Parsing **kultur-invariant** (Punkt *und* Komma als
      Dezimaltrennzeichen).

### Nicht-Ziele (bewusst ausgeklammert)

- Keine Live-Grafiken/Echtzeit-Dashboard.
- Keine zentrale Datenbank / kein Server.
- Keine CPU-/GPU-/Netz-Messung (nur Arbeitsspeicher).
- Kein Eingriff ins System (nur Lesen).

---

## 3. Empfehlungslogik (zur Prüfung)

- Zielgröße = **p99** des Commit Charge (praktischer Spitzenbedarf, robust gegen
  einzelne Ausreißer). Zusätzlich wird **Max** als Worst-Case ausgewiesen.
- Eine RAM-Größe gilt als komfortabel, wenn `Bedarf ≤ 0,80 × Größe`:
  - 16 GB bis ≈ 13 GB Bedarf
  - 32 GB bis ≈ 26 GB Bedarf
  - sonst 64 GB
- Wird Auslagerung > 50 Seiten/s gemessen → ausdrückliche Warnung.

**Cursor bitte prüfen:** Ist die 80-%-Schwelle sinnvoll? Sollte man zusätzlich
`Total − Available` (physisch tatsächlich genutzt) einbeziehen? Ist p99 die
richtige Zielgröße oder besser p95 / Max?

---

## 4. Ist-Zustand (Stand der Umsetzung)

Alle Funktionen F1–F17 sind **implementiert**. Umsetzungsdetails:

- Systemwerte über `Win32_OperatingSystem` (KB, sprachunabhängig) und
  ergänzend `Win32_PerfFormattedData_PerfOS_Memory` (mit Fallback, falls der
  Counter fehlt).
- Commit Charge doppelt abgesichert: OS-Ableitung
  (`TotalVirtualMemorySize − FreeVirtualMemory`) **und** Performance-Counter.
- Prozesse über `Get-Process`, gruppiert nach `ProcessName`, Top-25 einzeln,
  Rest als „(sonstige)".
- CSV via `Export-Csv -Append -Encoding UTF8` (Kopfzeile nur beim ersten Schreiben).
- Auswertung: eigene Perzentil-Funktion (lineare Interpolation), HTML mit
  Inline-CSS, `prefers-color-scheme`.

**Noch nicht getestet:** Die Skripte konnten in der Build-Umgebung nur statisch
geprüft werden (kein PowerShell verfügbar). Ein Live-Lauf auf echtem Windows 11
steht aus.

---

## 5. Prüfauftrag an Cursor

Bitte arbeite die folgenden Punkte ab und schreibe deine Ergebnisse in
[Abschnitt 7](#7-cursor-input-hier-ergänzen).

### 5.1 Korrektheit & Robustheit
1. **Syntax/Lauffähigkeit** auf **Windows PowerShell 5.1** *und* **PowerShell 7**:
   Gibt es inkompatible Konstrukte?
2. **CIM-Eigenschaften**: Sind alle verwendeten Properties von
   `Win32_PerfFormattedData_PerfOS_Memory` real vorhanden und korrekt benannt
   (`AvailableBytes`, `CommittedBytes`, `CommitLimit`,
   `PercentCommittedBytesInUse`, `CacheBytes`, `PageReadsPerSec`, `PagesPerSec`)?
3. **`Export-Csv -Append`**: Verhält sich der Header-Fall bei erster Messung
   korrekt? Risiko bei Spaltenreihenfolge?
4. **`CommittedBytes`-Wertebereich**: Kann der Counter überlaufen/abweichen?
   Ist die OS-Ableitung als Primärquelle die sicherere Wahl?
5. **Perzentil-Funktion**: Rechnet `Get-Percentile` bei 1 Messpunkt und bei
   sehr großen Datenmengen korrekt?
6. **Kultur-Parsing**: Deckt `ConvertTo-Double` alle Fälle ab (z. B. CSV auf
   deutschem System mit Komma erzeugt, auf englischem ausgewertet)?
7. **Fehlerpfade**: Was passiert, wenn ein Programm während der Messung
   beendet wird (`Get-Process`-Race)? Wenn der Ordner nicht schreibbar ist?

### 5.2 Methodik
8. Ist Commit Charge die richtige Leitgröße (siehe Abschnitt 1)? Sollte ein
   „was-wäre-wenn-16/32-GB"-Modell ergänzt werden (Cache-Effekt einrechnen)?
9. Ist die Empfehlungslogik (Abschnitt 3) belastbar?

### 5.3 Fehlende Features / Ausbau
10. Welche **fehlenden Features** würdest du ergänzen? (Kandidatenliste unten –
    bitte bewerten und erweitern.)

---

## 6. Kandidaten für fehlende Features (bitte bewerten/ergänzen)

Diese Liste ist bewusst offen. **Cursor: priorisieren (Muss/Kann/Nice), Aufwand
schätzen, eigene Ideen ergänzen.**

- [ ] **Automatischer Dauerbetrieb** über Tage inkl. **Tagesrotation** der CSV.
- [ ] **Mehrgeräte-/Mehrlauf-Vergleich** in einem gemeinsamen Bericht.
- [ ] **Zeitreihen-Diagramm** im HTML (Commit-Verlauf, ohne externe Libs, Inline-SVG).
- [ ] **Ereignis-Korrelation**: Zeitpunkt des Maximums + welche Programme dann
      liefen (Snapshot beim Peak).
- [ ] **Spitzen-Snapshot**: bei neuem Commit-Höchstwert vollständige
      Prozessliste zusätzlich sichern.
- [ ] **CSV-Aufbewahrung/Größenschutz** (Rotation, max. Dateigröße).
- [ ] **Konfigurationsdatei** statt nur Parameter.
- [ ] **Zusammenfassung mehrerer Läufe** (Arbeitswoche → ein Gesamtergebnis).
- [ ] **Schwellwert-Warnungen** (z. B. Hinweis, sobald Commit > X GB).
- [ ] **Export als CSV/PDF** des Auswertungs-Ergebnisses (nicht nur HTML).
- [ ] **Signierung / ExecutionPolicy**-Hinweise für gesperrte Firmen-PCs.
- [ ] **Getrennte Erfassung** von Standby-/Cache-Speicher für genauere „frei"-Zahl.
- [ ] **Sekundäre Kennzahlen** optional: CPU-Last je Programm zur Einordnung.

---

## 7. Cursor-Input (hier ergänzen)

> **Cursor: bitte alles ab hier ausfüllen.**

### 7.1 Gefundene Fehler / Risiken
_(Datei : Zeile — Beschreibung — Schweregrad — Fix-Vorschlag)_

- …

### 7.2 Bewertung der Methodik
- …

### 7.3 Empfohlene fehlende Features (priorisiert)
| Priorität | Feature | Nutzen | Aufwand | Anmerkung |
|---|---|---|---|---|
| | | | | |

### 7.4 Sonstige Empfehlungen
- …

---

## 8. Testszenarien (Abnahmekriterien)

1. **Leerlauf-Lauf** 10 min: CSV entsteht, Werte plausibel, Analyse läuft durch.
2. **Lastlauf**: Trimble Nova + Tinline Schema + Teams-Konferenz + 20 Browser-Tabs
   parallel öffnen → Commit-Peak sichtbar, Top-Verbraucher korrekt zugeordnet.
3. **Deutsches Windows**: keine Fehler durch lokalisierte Counter; Zahlen korrekt.
4. **Absturztest**: Fenster hart schließen → bereits geschriebene CSV bleibt
   auswertbar.
5. **Analyse ohne Prozess-CSV**: läuft trotzdem durch (nur Systembericht).
