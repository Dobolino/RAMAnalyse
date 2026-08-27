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

## 7. Review-Ergebnis (Cursor-Input)

> **Bearbeitet als Senior System Engineer / PowerShell-Experte.** Die Skripte
> wurden korrigiert und erweitert; Syntax mit PowerShell 7.4.6 geprüft
> (`Parser::ParseFile` → 0 Fehler) und die Analyse gegen synthetische Testdaten
> (2 Messtage sowie der Divergenz-Fall „hoher Commit / niedriger physischer
> Bedarf") real durchlaufen lassen.

### 7.1 Gefundene Fehler / Risiken

_Schweregrad: Hoch = falsche Entscheidung möglich · Mittel = Genauigkeit/Robustheit · Niedrig = Kosmetik. Status: ✅ behoben · ⚠️ offen/dokumentiert._

| # | Datei : Stelle | Beschreibung | Schwere | Korrektur | Status |
|---|---|---|---|---|---|
| **F1** | `Track-Memory.ps1` · `Get-ProcessSample` | `Get-Process`-Eigenschaften (`WorkingSet64` etc.) können werfen, wenn sich ein Prozess **während** der Messung beendet – unter `$ErrorActionPreference='Stop'` wäre der Messpunkt verloren. | Mittel | `Get-Process -ErrorAction SilentlyContinue`; Speicher-Properties je Prozess **sofort in try/catch** in einen Snapshot (`WS`/`PV`) gelesen, beendete Prozesse werden still übersprungen. | ✅ |
| **F2** | beide Skripte · alle CSV/HTML-Schreibvorgänge | UTF-8-Stabilität bei Pfaden mit Umlauten/Sonderzeichen auf PS 5.1 **und** 7. | Niedrig | Durchgängig `-Encoding UTF8` (Export-Csv) bzw. `Out-File -Encoding UTF8`; Rechnername/Pfad werden nicht mehr in Dateinamen-kritischer Weise zusammengesetzt (Tagesdatei-Schema). | ✅ |
| **F3** | `Track-Memory.ps1` · `Get-SystemSample` | Performance-Counter `Win32_PerfFormattedData_PerfOS_Memory` kann fehlen / einzelne Werte (`PagesPerSec`, `PageReadsPerSec`) 0 oder null liefern (erster Sample: Rate noch nicht berechenbar). | Mittel | Gesamte Counter-Abfrage in `try/catch`; **je Property** `if ($null -ne …)`-Guard mit Fallback auf die OS-abgeleiteten Werte. Kein Abbruch, keine Nullref. | ✅ |
| **F4** | `Analyze-Memory.ps1` · HTML/CSS | Dark-Mode-Kontrast der Tabelle „Größte Speicherverbraucher": Zeilentext auf hellem/alterniertem Grund schwer lesbar. | Mittel | Explizite `color:var(--fg)` auf `th,td`; Dark-Mode-Regel `td,th { color:#e2e8f0 }`; kontrastsichere Zebra-/Hover-Zeilen mit geringer Deckkraft. | ✅ |
| **F5** | `Analyze-Memory.ps1` · Empfehlung | Empfehlung nur nach Commit → **Fehlkauf-Gefahr** durch reservierten, aber ungenutzten Speicher. | Hoch (Kosten) | **Zwei-Faktor-Logik**: Hochstufung auf die nächste Klasse nur, wenn `Commit_p95` **und** `WorkingSet_Max (physisch ohne Cache)` die Schwellen überschreiten (32→64: p95 > 25,6 GB **und** WS > 22 GB). Sicherheits-Override, falls Commit die Klasse komplett übersteigt. | ✅ |
| **F6** | `Analyze-Memory.ps1` · Auslagerung | „> 50 Seiten/s = Mangel" ist zu grob (normales Nachladen löst Fehlalarm aus). | Mittel | Speicherdruck nur, wenn `PageReads > 50` **und** gleichzeitig `Available < max(1, 5% RAM)`. | ✅ |
| **F7** | `Analyze-Memory.ps1` · Konfidenz | Bei sehr wenigen Messpunkten ist p99 faktisch = Max; Nutzer sah das nicht. | Mittel | Rotes Banner bei **< 60 Messpunkten oder < 1 h**, inkl. Hinweis „p99 ≈ Max bei wenigen Punkten". | ✅ |
| **F8** | `Track-Memory.ps1` · Messschleife | Kein Festhalten, **welche Programme** beim höchsten Bedarf liefen. | Kann | **Peak-Snapshot**: bei neuem Commit-Höchstwert werden die **Top-5-Programme** (nach privatem Speicher) in die Spalte `PeakTop5` des Messpunkts geschrieben. | ✅ |
| **F9** | `Analyze-Memory.ps1` · Perzentil | Array-Index mit `[double]` (Coercion) unsauber; Einzelmesspunkt. | Niedrig | `[int]`-Cast der Indizes; Einzel-/Leerfall explizit behandelt. | ✅ |
| **F10** | `Track-Memory.ps1` · Zähler | Working-Set-**Summe** über Prozesse überzählt geteilte Seiten. | Mittel | In der Auswertung wird **privater Speicher** zur Leit-/Sortiergröße je Programm; Working Set nur als Anhalt gezeigt. | ✅ |
| **R1** | `Track-Memory.ps1` · CSV-Delimiter | Deutsches Excel erwartet beim Doppelklick `;` → Spalten verrutschen (für die Skript-Auswertung irrelevant). | Niedrig | In README dokumentiert (Import über „Daten → Text-in-Spalten"). Optionaler `-Delimiter ';'` als möglicher Ausbau. | ⚠️ dokumentiert |
| **R2** | `Track-Memory.ps1` · harter Abbruch | Letzte CSV-Zeile evtl. unvollständig. `Import-Csv` verwirft sie i. d. R. | Niedrig | Beobachten; optionaler Zeilen-Konsistenzcheck als Ausbau. | ⚠️ offen |

**Kein verbleibender Fund mit Schwere „Hoch".** Der kostenrelevanteste Punkt
(**F5**, Fehlkauf durch reine Commit-Betrachtung) ist behoben.

### 7.2 Bewertung der Methodik

- **Commit Charge als Leitgröße – richtig, aber als *Obergrenze* zu lesen.**
  Commit ist die einzige RAM-größenunabhängige Bedarfszahl (entspricht „Zugesichert"
  im Task-Manager). Sie beschreibt jedoch **reservierten**, nicht zwingend
  **residenten** Speicher.
- **Working-Set-Inflation auf dem 64-GB-Testgerät (zentral!).** Browser (Chrome,
  Brave, Edge/`msedgewebview2`) und Electron-Apps (Teams, Slack, auch der
  Cursor-Editor) belegen auf einem 64-GB-System **mehr** Speicher, als sie auf
  einem 32-GB-System aktiv nutzen würden: Erst bei Knappheit greifen Memory
  Pressure und Garbage Collection und geben Speicher zurück. Ein reiner
  Commit-Vergleich vom 64-GB-Gerät **überschätzt** daher den Bedarf auf einem
  kleineren Gerät. → Deshalb die **Zwei-Faktor-Empfehlung** (F5): Hochstufen nur,
  wenn auch der **physisch belegte** Speicher (ohne Cache) hoch ist.
- **p99 vs. p95.** p99 ist der konservative Dauer-Spitzenwert und gut für die
  Ampel. Für die *Kaufschwelle* nutzt die neue Logik bewusst **p95** (robuster
  gegen einzelne Ausreißer) – deckt sich mit der geforderten Schwelle
  `Commit_p95 > 26 GB`. **Wichtig:** Bei < 60 Messpunkten liegen p95, p99 und Max
  praktisch übereinander → dann ist die Aussage schwach (Konfidenz-Banner, F7).
- **Cache-Verhalten.** Freier RAM wird als Datei-Cache genutzt (beschleunigt das
  Laden großer CAD-Pläne) und lässt „belegt" hoch aussehen. Die Auswertung rechnet
  den Cache heraus (`PhysicalInUse − Cache`) und plant zugleich ~20 % Reserve ein
  (80-%-Regel), damit auf dem Zielgerät genug Cache übrig bleibt.
- **Fazit:** Kernannahme bestätigt, aber um die physische Gegenprobe ergänzt –
  dadurch **kaufmännisch belastbar** (verhindert sowohl Unter- als auch
  Überdimensionierung).

### 7.3 Empfohlene fehlende Features

| Feature | Priorität | Nutzen | Aufwand | Anmerkung / Status |
|---|---|---|---|---|
| Tagesrotation der CSV (Mehrtages-Messung) | Muss | Belastbare Basis über mehrere Tage, begrenzter Datenverlust | S | ✅ umgesetzt |
| Multi-Run-Aggregation + Aufschlüsselung pro Tag | Muss | Beantwortet „5 Tage fließen zusammen ein" | M | ✅ umgesetzt |
| Peak-Snapshot (Top-5 / „Was lief beim Höchststand?") | Muss | Zentrales Argument in der Beschaffung | S | ✅ umgesetzt (Logger-Spalte + HTML-Rekonstruktion) |
| Konfidenz-Warnung (< 60 Punkte / < 1 h) | Muss | Verhindert Fehlentscheidung aus Kurzmessung | S | ✅ umgesetzt |
| Zwei-Faktor-Empfehlung (Commit **und** Working Set) | Muss | Verhindert Fehlkäufe | M | ✅ umgesetzt |
| Zeitreihen-Diagramm (Inline-SVG) | Kann | Überzeugt Entscheider visuell | M | ✅ umgesetzt |
| Mehrgeräte-Vergleich in **einem** Bericht | Kann | Test-PCs direkt gegenüberstellen | M | offen – aktuell je Rechner ein Bericht (`-Machine`) |
| CSV-Zeilen-Konsistenzcheck (kaputte letzte Zeile) | Kann | Robuster nach hartem Abbruch | S | offen (R2) |
| Schwellwert-Live-Warnung im Logger (Commit > X) | Nice | Frühwarnung während der Messung | S | offen |
| Optionaler `;`-Delimiter für DE-Excel | Nice | Direktes Öffnen in Excel | S | offen (R1, dokumentiert) |
| CPU-Last je Programm (Sekundärkennzahl) | Nice | Einordnung, außerhalb des RAM-Ziels | M | bewusst nicht umgesetzt |

### 7.4 Sonstige Empfehlungen (Rollout im Elektroplanungs-Umfeld)

- **ExecutionPolicy:** Die `.cmd`-Starter nutzen bereits
  `-ExecutionPolicy Bypass -File …` (nur für diesen Aufruf, keine dauerhafte
  Systemänderung). Auf per GPO gesperrten Firmen-PCs ggf. mit der IT abstimmen
  (alternativ Skripte signieren) – als bekannter Punkt dokumentiert.
- **Unter echter CAD-Last testen:** Aussagekräftig wird die Messung nur mit dem
  realen Arbeitsmix – **Trimble Nova + Tinline Schema gleichzeitig**, dazu große
  Projekte/Pläne öffnen, Teams-Videokonferenz, IP-Telefonie und die üblichen
  Browser-Tabs. Bewusst auch Plan-Wechsel/Regenerieren provozieren (Speicherspitzen).
- **Mehrere volle Arbeitstage** und – wenn möglich – **mehrere Arbeitsplatztypen**
  (Planung vs. reine Office-Nutzung) messen; die Profile getrennt bewerten.
- **Autostart** über die geplante Aufgabe (siehe README), damit die Messung
  Neustarts übersteht und über Mitternacht (Tagesrotation) durchläuft.
- **Reserve einplanen:** Die Empfehlung bildet den **heutigen** Arbeitsstil ab.
  Trimble-/Office-Updates tendieren zu höherem Bedarf → nicht am absoluten Limit
  kaufen; bei „Grenzwertig" die nächstgrößere Klasse wählen.
- **Datenschutz:** Nur Speicherzahlen und Programmnamen werden erfasst – vor dem
  Rollout dem Betriebsrat/DSB kurz transparent machen (steht so im README).

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
