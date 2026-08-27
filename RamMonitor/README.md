# RAM-Monitor – Arbeitsspeicher-Bedarf pro Programm messen

Werkzeug für Windows 11, um über Tage hinweg zu protokollieren, wie viel
Arbeitsspeicher ein PC **wirklich** braucht – systemweit und pro Programm.
Ziel: fundiert entscheiden, ob für die neuen Arbeitsplätze **16, 32 oder 64 GB**
RAM nötig sind, statt auf Verdacht das teuerste Modell zu beschaffen.

- **Keine Installation nötig** – reines PowerShell, auf jedem Windows vorhanden.
- **Keine Adminrechte nötig** für die Messung.
- **Läuft im Hintergrund** über Stunden/Tage, schreibt CSV-Dateien.
- **Auswertung** erzeugt eine klare Empfehlung + HTML-Bericht für die Beschaffung.

Gedacht für den 64-GB-Testrechner: dort wird der echte Bedarf des typischen
Arbeitsalltags (Trimble Nova, Tinline Schema, Office, Videokonferenz,
IP-Telefonie, Browser …) gemessen und daraus abgeleitet, welche RAM-Größe für
die künftigen Geräte ausreicht.

---

## Schnellstart

1. Ordner `RamMonitor` auf den **Testrechner** kopieren (z. B. auf den Desktop).
2. **Messung starten:** Doppelklick auf **`Messung-starten.cmd`**.
   Ein Fenster öffnet sich und zeigt fortlaufend die Messwerte. **Fenster
   offen lassen** und ganz normal weiterarbeiten – am besten einen typischen
   Arbeitstag lang, gern mehrere Tage und mit allen Programmen gleichzeitig,
   die im Alltag laufen.
3. **Messung beenden:** Fenster anklicken und **STRG+C** drücken (oder Fenster
   schließen).
4. **Auswerten:** Doppelklick auf **`Auswertung-starten.cmd`**. Es erscheint
   eine Zusammenfassung im Fenster, und der **HTML-Bericht** öffnet sich
   automatisch im Browser – ideal zum Weiterleiten.

> Tipp: Für ein belastbares Ergebnis an einem „schweren" Tag messen – wenn
> mehrere CAD-Projekte, Videokonferenz und viele Browser-Tabs gleichzeitig
> offen sind. Der **Spitzenbedarf** entscheidet über die richtige RAM-Größe.

### Über mehrere Tage messen (wichtig!)

Du kannst die Messung **an mehreren Tagen** starten – die Auswertung fasst
**automatisch alle Messungen zusammen** und rechnet daraus ein Gesamtergebnis.

- Der Logger legt **pro Tag eine Datei** an (Tagesrotation). Startest du an
  einem Tag mehrmals, wird an dieselbe Tagesdatei angehängt (durchgehende
  Zeitachse).
- Misst du also z. B. an 5 Tagen, entstehen 5 Tagesdateien – und
  `Auswertung-starten.cmd` wertet **alle 5 gemeinsam** aus (Spitze und p99 über
  die gesamte Woche). Zusätzlich zeigt der Bericht eine **Aufschlüsselung pro
  Messtag**.
- **Nichts löschen** zwischen den Tagen – einfach die Dateien im Ordner
  `Messdaten` liegen lassen. Je mehr echte Arbeitstage, desto belastbarer die
  Empfehlung.
- Läuft die Messung über Mitternacht durch, wechselt der Logger selbstständig
  auf die Datei des neuen Tages.

> Der Bericht warnt deutlich, wenn die Messung **zu kurz** war (zu wenige
> Messpunkte / zu kurze Dauer) – dann ist die Empfehlung noch nicht belastbar.

### Mehrere Test-PCs

Der Rechnername steht im Dateinamen. Liegen im selben Ordner Messungen
verschiedener PCs, wertet der Bericht standardmäßig den PC mit den meisten
Messpunkten aus und weist auf die anderen hin. Gezielt auswerten:

```powershell
.\Analyze-Memory.ps1 -Machine PC-NAME
```

---

## Was wird gemessen?

Die entscheidende Kennzahl ist der **zugesicherte Speicher (Commit Charge)** –
die Menge, die **alle Programme zusammen tatsächlich angefordert** haben. Sie
ist unabhängig davon, wie viel RAM verbaut ist, und deshalb die belastbare
Grundlage für die Beschaffung.

> Warum nicht einfach die „belegt"-Anzeige im Task-Manager? Windows nutzt freien
> RAM automatisch als Datei-Cache. Auf einem 64-GB-Rechner sieht „belegt"
> deshalb immer hoch aus, obwohl ein 32-GB-Rechner denselben Arbeitsablauf
> problemlos schaffen würde. Commit Charge misst den echten Bedarf.

Zusätzlich erfasst das Tool:

| Kennzahl | Bedeutung |
|---|---|
| Commit Charge | Angeforderter Speicher aller Programme (**Hauptkennzahl**) |
| Physisch belegt / frei | Aktuelle RAM-Nutzung bzw. -Reserve |
| Auslagerung (Seiten/s) | Nachladen von der Platte – hohe Werte = Speichermangel |
| Pro Programm | Arbeitsspeicher (Working Set) und privater Speicher je Programm |

---

## Wie entsteht die Empfehlung?

- Aus allen Messpunkten werden **Maximum** und die **Perzentile p95/p99**
  des Commit Charge gebildet. p99 = praktischer Spitzenbedarf, unempfindlich
  gegen einen einzelnen Ausreißer.
- Eine RAM-Größe gilt als **komfortabel**, wenn der Bedarf rund **80 %** davon
  nicht überschreitet (die restlichen 20 % bleiben als Reserve für Spitzen und
  Datei-Cache, der z. B. das Laden großer CAD-Pläne beschleunigt).
  - 16 GB komfortabel bis ~13 GB Bedarf
  - 32 GB komfortabel bis ~26 GB Bedarf
  - darüber: 64 GB
- Wird auf dem 64-GB-Testgerät **Auslagerung** gemessen, war schon dort
  zeitweise Speicherdruck – dann ist von kleineren Größen abzuraten. Das wird
  im Bericht ausdrücklich vermerkt.

Der Bericht nennt getrennt die Empfehlung für den **Dauerbedarf (p99)** und für
**seltene Spitzen (Maximum)**, damit ihr die Abwägung transparent trefft.

Der HTML-Bericht zeigt das laienverständlich als **Ampel** („reicht welche
Größe?" mit grün/gelb/rot), als **Verlaufs-Diagramm**, mit **Erklärungen zu
jeder Zahl** (Info-Symbole zum Überfahren) und einem **Glossar**. Zusätzlich:
„Was lief beim Höchststand?" (die offenen Programme im Moment des höchsten
Bedarfs) und eine Aufschlüsselung pro Messtag.

> Hinweis zur Auslagerung: Als „Speicherdruck" wird sie nur gewertet, wenn
> **gleichzeitig wenig RAM frei** war. Normales Nachladen von Programmdateien
> (ohne Knappheit) löst also keinen Fehlalarm aus.

### Zwei Berichte + Excel-Zusammenfassung

Die Auswertung erzeugt standardmäßig **zwei Berichte** für unterschiedliche
Zielgruppen plus eine CSV:

| Datei | Für wen | Inhalt |
|---|---|---|
| **`Einfach-Bericht_*.html`** | IT-Verantwortlicher / normale Leser | Ein-Seiter: klare Empfehlung, grün/gelb/rot in Klartext, „Was bedeutet das?", keine Fachbegriffe |
| **`IT-Detailbericht_*.html`** | IT / Technik | Alles: Ampel, Verlauf, Kennzahlen, pro Messtag, Höchststand, **technische Details** (alle Perzentile, Schwellenwerte, Methodik, Datenquellen) |
| **`Zusammenfassung_*.csv`** | IT / Excel | Eine Zeile mit allen Kennzahlen zum Weiterverarbeiten |

Beim Doppelklick auf `Auswertung-starten.cmd` öffnen sich **beide** Berichte
automatisch. Gezielt nur einen erzeugen:

```powershell
.\Analyze-Memory.ps1 -Zielgruppe Einfach   # nur der einfache Ein-Seiter
.\Analyze-Memory.ps1 -Zielgruppe IT        # nur Detailbericht + CSV
.\Analyze-Memory.ps1 -Zielgruppe Beide     # Standard: alles
```

> Aus jedem HTML-Bericht wird per Browser **Drucken → „Als PDF speichern"** ein
> PDF zum Verschicken – ganz ohne Zusatzsoftware.

---

## Manuelle Nutzung (PowerShell)

```powershell
# Messung: alle 30 Sekunden, 8 Stunden lang
.\Track-Memory.ps1 -IntervalSeconds 30 -DurationMinutes 480

# Auswertung der neuesten Messung (HTML-Bericht wird erzeugt)
.\Analyze-Memory.ps1

# Auswertung bestimmter Dateien
.\Analyze-Memory.ps1 -SystemCsv .\Messdaten\system_PC01_2026-08-27_08-00-00.csv `
                     -ProcessCsv .\Messdaten\prozesse_PC01_2026-08-27_08-00-00.csv
```

### Parameter `Track-Memory.ps1`

| Parameter | Standard | Bedeutung |
|---|---|---|
| `-IntervalSeconds` | 60 | Messintervall in Sekunden |
| `-DurationMinutes` | 0 | Laufzeit (0 = bis STRG+C) |
| `-OutputFolder` | `.\Messdaten` | Zielordner für die CSV-Dateien |
| `-TopProcesses` | 25 | Anzahl einzeln erfasster Top-Programme |

---

## Über mehrere Tage / automatisch messen

Damit die Messung auch nach Neustart automatisch weiterläuft, als geplante
Aufgabe einrichten (einmalig in einer PowerShell **als Administrator**):

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Pfad\zu\RamMonitor\Track-Memory.ps1"'
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName 'RAM-Monitor' -Action $action -Trigger $trigger -RunLevel Limited
```

Entfernen mit: `Unregister-ScheduledTask -TaskName 'RAM-Monitor' -Confirm:$false`

---

## Datenschutz / Umfang

Erfasst werden **nur** Speicher-Kennzahlen und **Programmnamen** (z. B.
`Trimble.Nova`, `OUTLOOK`, `Teams`). **Keine** Fenstertitel, Dateinamen,
Tastatureingaben oder Inhalte. Die CSV-Dateien bleiben lokal im Ordner
`Messdaten` und werden nirgendwohin gesendet.
