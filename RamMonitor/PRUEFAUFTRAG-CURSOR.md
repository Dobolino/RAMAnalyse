# Prüfauftrag & Anforderungsbericht – RAM-Monitor

> **Status: Review durchgeführt.** Die Skripte wurden statisch gegen die
> Anforderungen geprüft. Ergebnisse stehen in [Abschnitt 7](#7-review-ergebnis).
> Die Soll-Funktionen (Abschnitt 2) sind abgehakt, die Feature-Kandidaten
> (Abschnitt 6) bewertet.

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

### Fachliche Kernannahme

Maßgeblich ist der **zugesicherte Speicher (Commit Charge)**, nicht die
„belegt"-Anzeige. Begründung: Windows nutzt freien RAM als Datei-Cache, daher
ist „belegt" auf einem 64-GB-Gerät künstlich hoch. Commit Charge = tatsächlich
angeforderter Speicher, unabhängig vom verbauten RAM → richtige Basis für die
Dimensionierung.

> **Review-Urteil:** Die Annahme ist **methodisch korrekt** – mit einer
> Präzisierung, siehe [7.2](#72-bewertung-der-methodik).

---

## 2. Soll-Funktionen (geprüft)

### Messung (`Track-Memory.ps1`)

- [x] **F1** Ohne Installation / ohne Adminrechte. *Bestätigt: nur Bordmittel
      (`Get-CimInstance`, `Get-Process`), kein Schreibzugriff außerhalb des Ordners.*
- [x] **F2** Festes Intervall, parametrierbar (`-IntervalSeconds`, Standard 60).
- [x] **F3** Systemweite Kennzahlen vorhanden (Commit, Grenze, %, belegt/frei,
      verfügbar, Cache, Auslagerung).
- [x] **F4** Pro Programm Working Set + privat, Top-N + „(sonstige)".
- [x] **F5** Sofort-Schreiben je Messpunkt. *Einschränkung B7 (Teilzeile bei
      hartem Kill) – unkritisch.*
- [x] **F6** Locale-robust: CIM-Klassen mit englischen Property-Namen, keine
      lokalisierten Counter-Pfade. *Bestätigt.*
- [x] **F7** Unbegrenzt bis STRG+C oder `-DurationMinutes`.
- [x] **F8** Dateinamen mit Rechnername + Startzeit.
- [x] **F9** Live-Statuszeile, Auslagerung rot hervorgehoben.
- [x] **F10** Datenschutz: nur Zahlen + Programmnamen. *Bestätigt – keine
      Fenstertitel/Pfade/Inhalte.*

### Auswertung (`Analyze-Memory.ps1`)

- [x] **F11** Automatische Auswahl der neuesten Messung / explizite Pfade.
- [x] **F12** Max, p99, p95, Median, Mittelwert des Commit Charge.
- [x] **F13** Empfehlung 16/32/64 GB (80-%-Regel), getrennt p99 / Max.
- [x] **F14** Auslagerungs-Warnung. *Aber: Schwelle allein ist zu grob – B1.*
- [x] **F15** Tabelle der größten Verbraucher.
- [x] **F16** HTML-Bericht (light/dark).
- [x] **F17** Kultur-invariantes Parsing (`ConvertTo-Double`, Komma→Punkt).
      *Bestätigt inkl. CSV-Rückweg: `Export-Csv` quotet Felder, daher sind
      Komma-Dezimalzahlen trotz Komma-Trennzeichen eindeutig.*

**Ergebnis:** Alle Soll-Funktionen sind umgesetzt. Kein Blocker gefunden. Die
Funde betreffen Randfälle und methodische Schärfung.

---

## 3. Empfehlungslogik – Bewertung

Die Logik (p99 als Zielgröße, 80-%-Regel, Max als Worst-Case, Auslagerungs-
Warnung) ist **grundsätzlich belastbar**. Verbesserungen siehe
[7.2](#72-bewertung-der-methodik). Kurzantworten auf die gestellten Fragen:

- **80-%-Schwelle sinnvoll?** Ja als Daumenwert. Für CAD mit großen Plänen eher
  konservativ bleiben (75 %), damit genug Datei-Cache bleibt → schnelleres Laden.
- **`Total − Available` einbeziehen?** Ja, als Gegenprobe (physisch real
  genutzt). Ist bereits als `PhysicalInUseGB` erfasst, fließt aber noch nicht in
  die Empfehlung ein – siehe Empfehlung in 7.2.
- **p99 richtig?** Ja für den Dauerbedarf. Zusätzlich Max ausweisen (passiert).
  p95 ist bei sehr kurzen Messreihen aussagekräftiger als p99.

---

## 4. Ist-Zustand

Alle Funktionen F1–F17 implementiert. Umsetzung wie im Code dokumentiert
(OS-Ableitung + Performance-Counter mit Fallback, `Get-Process`-Gruppierung,
`Export-Csv -Append`, eigene Perzentil-Funktion, HTML mit Inline-CSS).

**Nicht live getestet:** Statische Prüfung erfolgt; ein Lauf auf echtem
Windows 11 (5.1 und 7) steht noch aus – siehe Abnahme in Abschnitt 8.

---

## 5. Prüfauftrag (Fragenkatalog)

Beantwortet in [Abschnitt 7](#7-review-ergebnis).

---

## 6. Feature-Kandidaten – bewertet

Legende Priorität: **Muss** / **Kann** / **Nice**. Aufwand: S/M/L.

| Feature | Prio | Aufwand | Bewertung |
|---|---|---|---|
| Automatischer Dauerbetrieb + **Tagesrotation** der CSV | **Muss** | S | Für eine Mehrtages-Messung nötig; verhindert Riesendateien und begrenzt Datenverlust auf einen Tag. |
| **Zeitreihen-Diagramm** im HTML (Inline-SVG, ohne Libs) | **Muss** | M | Macht den Bericht für die Geschäftsführung überzeugend – Verlauf zeigt Spitzen im Tagesgang. |
| **Spitzen-Snapshot** beim Commit-Höchstwert (volle Prozessliste) | **Muss** | S | Beantwortet „*Was lief, als der Speicher am knappsten war?*" – zentrales Argument. |
| **Mehrgeräte-/Mehrlauf-Vergleich** in einem Bericht | Kann | M | Sinnvoll, sobald mehrere Test-PCs/Tage vorliegen. |
| **Zusammenfassung mehrerer Läufe** (Arbeitswoche → Gesamt) | Kann | M | Aggregiert p99 über alle Läufe – robustere Beschaffungsbasis. |
| **Schwellwert-Warnungen** (Hinweis, sobald Commit > X GB) | Kann | S | Nützlich, aber nachrangig zur reinen Datensammlung. |
| **CSV-Größenschutz** (max. Größe / Aufbewahrung) | Kann | S | Durch Tagesrotation weitgehend abgedeckt. |
| **ExecutionPolicy/Signierung**-Hinweise (gesperrte Firmen-PCs) | Kann | S | `.cmd`-Starter nutzt `-ExecutionPolicy Bypass`; bei per GPO gesperrten PCs dokumentieren. |
| **Getrennte Standby-/Cache-Erfassung** (genauere „frei"-Zahl) | Nice | M | Verfeinert die Interpretation, nicht entscheidend. |
| **Konfigurationsdatei** statt Parameter | Nice | S | Komfort; Parameter genügen aktuell. |
| **CPU-Last je Programm** (Sekundärkennzahl) | Nice | M | Außerhalb des Ziels (nur RAM), höchstens optional. |
| **PDF-Export** des Berichts | Nice | S | HTML per „Drucken → PDF" reicht meist. |
| **Eigene Ideen (Reviewer):** | | | |
| → **Cache-bereinigter Bedarf** `Committed` + kleiner Cache-Sockel als „Ziel-RAM auf kleinerem Gerät" | **Muss** | S | Modelliert direkt: *„16/32 GB – reicht das?"* statt nur Rohbedarf. |
| → **Konsistenzprüfung/Warnungen** bei lückenhaften/kaputten CSV-Zeilen | Kann | S | Robuster gegen abgebrochene Läufe. |
| → **Konfidenz-Hinweis** bei zu kurzer Messdauer (< N Messpunkte) | Kann | S | Verhindert Fehlentscheidungen aus 5-Minuten-Messungen. |

---

## 7. Review-Ergebnis

### 7.1 Gefundene Punkte / Risiken

_Schweregrad: Hoch = falsche Entscheidung möglich · Mittel = Genauigkeit/Robustheit · Niedrig = Kosmetik._

| # | Datei : Zeile | Beschreibung | Schwere | Fix-Vorschlag |
|---|---|---|---|---|
| **B1** | `Analyze-Memory.ps1:157`, `Track-Memory.ps1:211` | „Auslagerung > 50 Seiten/s = Speichermangel" ist **zu grob**. `PageReadsPerSec` zählt auch normales Nachladen speichergemappter Dateien (EXE/DLL-Start, CAD-Datei öffnen) – auch **ohne** RAM-Mangel. Kann Fehlalarm auslösen. | Mittel | Nur als Mangel werten, wenn **gleichzeitig** wenig verfügbar (`AvailableGB` niedrig). Kennzahl `lowAvailSamples` existiert bereits (Zeile 130) – mit Auslagerung koppeln. |
| **B2** | `Track-Memory.ps1:158`, `Analyze:174` | Summe der **Working Sets** über Prozesse **überzählt gemeinsame Seiten** (dieselbe DLL zählt in jedem Prozess). Per-App-Working-Set ist dadurch eher zu hoch. | Mittel | Für die Größen-Einschätzung **privaten Speicher** (`PrivateGB`) betonen; Working Set nur als Anhalt. In der Tabelle privat gleichwertig zeigen (ist erfasst). |
| **B3** | `Analyze-Memory.ps1:146-147` | Empfehlung stützt sich **nur** auf Commit Charge. Der physisch real genutzte Speicher (`PhysicalInUseGB`, ohne Cache) fließt nicht ein – als Gegenprobe sinnvoll. | Mittel | Zweite Kennzahl bilden: `max(PhysicalInUse) − Cache` und Empfehlung als **Maximum aus beiden** Wegen wählen. |
| **B4** | `Track-Memory.ps1:118-121` | Erste `Win32_PerfFormattedData_*`-Abfrage liefert für **PerSec-Werte** oft 0/unzuverlässig (Rate braucht zwei Snapshots). Betrifft nur den ersten Messpunkt. | Niedrig | Ersten Messpunkt verwerfen **oder** einmal „aufwärmen" (Doppelabfrage vor der Schleife). |
| **B5** | `Track-Memory.ps1:121,123` | Der OS-abgeleitete Commit (Zeile 107) wird durch den Counter **überschrieben**. Beide sind gültig, aber die OS-Ableitung ist die stabilere Primärquelle. | Niedrig | OS-Ableitung als führend belassen; Counter nur für Verfügbar/Cache/Auslagerung nutzen (oder beide Spalten führen). |
| **B6** | `Track-Memory.ps1:73,101` | `TotalVisibleMemorySize` **unterschätzt** den physischen RAM leicht (hardware-reservierter Speicher fehlt) – z. B. 63,8 statt 64 GB. Kosmetisch. | Niedrig | Für die reine Anzeige `Win32_ComputerSystem.TotalPhysicalMemory` (Bytes) verwenden; für „belegt/frei" bleibt die OS-Klasse richtig. |
| **B7** | `Track-Memory.ps1:204-205` | Bei hartem Abbruch **während** des Schreibens kann die letzte CSV-Zeile unvollständig sein. `Import-Csv` verkraftet das meist (verwirft die Zeile). | Niedrig | Optional: Konsistenzcheck in der Auswertung (Zeilen mit falscher Spaltenzahl überspringen). |
| **B8** | `Track-Memory.ps1:154-159` | `Get-Process`-Eigenschaften können werfen, wenn ein Prozess **während** der Messung endet. Wegen `$ErrorActionPreference='Stop'` bräche die Messung ab – ist aber durch das try/catch der Schleife (197-219) abgefangen (Messpunkt geht verloren, Lauf läuft weiter). | Niedrig | Zugriff je Prozess kapseln **oder** `Get-CimInstance Win32_Process` (Snapshot) nutzen, um Datenverlust einzelner Punkte zu vermeiden. |
| **B9** | `Track-Memory.ps1:204-205` | CSV wird mit **Komma-Trennzeichen** geschrieben. Doppelklick auf deutschem Excel (erwartet `;`) landet in **einer** Spalte. Für die Auswertung via Skript irrelevant. | Niedrig | Im README notieren („Excel: Daten → Text-in-Spalten") oder optional `-Delimiter ';'` (dann Import ebenso). |
| **B10** | `Analyze-Memory.ps1:105-109` | Array-Index mit `[double]` (`[math]::Floor`) funktioniert per PS-Coercion, ist aber unsauber. Einzelmesspunkt wird korrekt behandelt (getestet gedanklich). | Niedrig | `[int]` casten: `$sorted[[int]$low]`. |

**Kein Fund mit Schwere „Hoch".** Die zwei entscheidungsrelevanten Punkte sind
**B1** (Fehlalarm Auslagerung) und **B3** (Empfehlung nur auf Commit) – beide
klein umzusetzen und in 7.3 als „Muss" priorisiert.

### 7.2 Bewertung der Methodik

- **Commit Charge als Leitgröße: richtig.** Sie ist die einzige RAM-größen-
  **unabhängige** Bedarfszahl und entspricht dem, was der Task-Manager als
  „Zugesichert" zeigt. Die reine „belegt"-Anzeige wäre irreführend (Cache).
- **Präzisierung:** Commit ist eine leichte **Obergrenze** des physischen
  Bedarfs (nicht alles Zugesicherte ist gleichzeitig aktiv im RAM). Für die
  Entscheidung ist das die **sichere Richtung** (lieber etwas großzügig).
  Als Gegenprobe sollte zusätzlich `PhysicalInUse − Cache` betrachtet werden
  (B3); die Empfehlung nimmt dann das Maximum beider Wege.
- **„Was-wäre-wenn-16/32-GB"-Modell empfohlen:** Ein kleineres Gerät hat weniger
  Cache. Faustregel: Ziel-Bedarf ≈ `Commit-p99` + kleiner Cache-Sockel
  (~1–2 GB Betriebsreserve). Reicht die Kandidatengröße mit 20–25 % Luft, ist
  sie komfortabel. Genau das leistet die 80-%-Regel bereits – gut.
- **Aussagekraft = Messdauer.** Eine belastbare Empfehlung braucht **echte
  Lastphasen** (mehrere CAD-Projekte + Videokonferenz gleichzeitig) und
  idealerweise mehrere Tage. Kurze Messungen unterschätzen den Spitzenbedarf.
  Empfehlung: Konfidenz-Hinweis bei zu wenigen Messpunkten (7.3).

### 7.3 Empfohlene Umsetzung (priorisiert)

| Prio | Punkt | Bezug | Aufwand |
|---|---|---|---|
| 1 | Auslagerung nur mit **wenig-verfügbar** koppeln | B1 | S |
| 2 | Empfehlung = **max(Commit-Weg, PhysInUse−Cache-Weg)**; privaten Speicher betonen | B3, B2 | S |
| 3 | **Tagesrotation** der CSV für Mehrtages-Messung | Feature | S |
| 4 | **Spitzen-Snapshot** beim Commit-Höchstwert (volle Prozessliste) | Feature | S |
| 5 | **Zeitreihen-Diagramm** (Inline-SVG) im HTML | Feature | M |
| 6 | **Konfidenz-Hinweis** bei < N Messpunkten + Konsistenzcheck kaputter Zeilen | B7, Feature | S |
| 7 | Kosmetik/Robustheit: B4, B5, B6, B10 | – | S |

### 7.4 Sonstige Empfehlungen

- **Vor der echten Messung** einen 10-Minuten-Probelauf machen und Analyse
  durchlaufen lassen (Abnahme Szenario 1), um Pfade/Rechte zu verifizieren.
- **Messfenster gezielt wählen:** ein „schwerer" Tag mit maximaler Parallel-Last
  bringt den aussagekräftigsten Spitzenwert.
- **Beschaffungsempfehlung** immer mit der Bemerkung versehen, dass die Zahl den
  **gemessenen** Arbeitsstil abbildet; künftige Software-Updates (Trimble/Office)
  tendieren erfahrungsgemäß zu höherem Bedarf → nicht am absoluten Limit planen.

---

## 8. Testszenarien (Abnahmekriterien)

1. **Leerlauf-Lauf** 10 min: CSV entsteht, Werte plausibel, Analyse läuft durch.
2. **Lastlauf**: Trimble Nova + Tinline Schema + Teams-Konferenz + 20 Browser-Tabs
   parallel öffnen → Commit-Peak sichtbar, Top-Verbraucher korrekt zugeordnet.
3. **Deutsches Windows**: keine Fehler durch lokalisierte Counter; Zahlen korrekt.
4. **Absturztest**: Fenster hart schließen → bereits geschriebene CSV bleibt
   auswertbar.
5. **Analyse ohne Prozess-CSV**: läuft trotzdem durch (nur Systembericht).
6. **PowerShell-Versionen**: je einmal unter Windows PowerShell **5.1** und
   PowerShell **7** starten (Syntax ist zu beiden kompatibel – bitte real
   bestätigen).
