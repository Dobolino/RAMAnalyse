<#
.SYNOPSIS
    Wertet die von Track-Memory.ps1 erzeugten CSV-Dateien aus und gibt eine
    RAM-Empfehlung (16 / 32 / 64 GB) samt HTML-Bericht aus.

.BESCHREIBUNG
    Kernidee der Auswertung:
      * Massgeblich ist die zugesicherte Speichermenge (Commit Charge). Sie
        beschreibt den echten Bedarf und ist unabhaengig vom verbauten RAM.
      * Es werden Maximum sowie die Perzentile p50/p95/p99 gebildet. Ein
        einzelner Ausreisser (Max) muss die Beschaffung nicht bestimmen -
        p95/p99 zeigt den praktischen Dauerbedarf.
      * Fuer eine Speichergroesse gilt sie als komfortabel, wenn der Bedarf
        rund 80% der Groesse nicht ueberschreitet (Rest = Reserve fuer Spitzen
        und Datei-Cache, der z.B. das Laden grosser CAD-Plaene beschleunigt).
      * Zusaetzlich wird die Auslagerung (harte Seitenfehler) geprueft. Auf dem
        64-GB-Testgeraet sollte sie ~0 sein; taucht sie auf, wird es eng.

.PARAMETER SystemCsv
    Pfad zur system_*.csv. Wenn leer, wird die neueste im Ordner "Messdaten"
    (bzw. -InputFolder) verwendet.

.PARAMETER ProcessCsv
    Pfad zur prozesse_*.csv. Wenn leer, wird die passende neueste gesucht.

.PARAMETER InputFolder
    Ordner, in dem nach den neuesten CSV-Dateien gesucht wird, falls keine
    Pfade angegeben sind. Standard: Unterordner "Messdaten" neben dem Skript.

.PARAMETER OutputHtml
    Pfad fuer den HTML-Bericht. Standard: Bericht_<Zeitstempel>.html im
    Eingabeordner.

.BEISPIEL
    .\Analyze-Memory.ps1
    Nimmt automatisch die neueste Messung und erzeugt Konsolenausgabe + HTML.
#>

[CmdletBinding()]
param(
    [string]$SystemCsv,
    [string]$ProcessCsv,
    [string]$InputFolder,
    [string]$OutputHtml
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Eingabedateien bestimmen
# ---------------------------------------------------------------------------
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($InputFolder)) {
    $InputFolder = Join-Path $scriptDir 'Messdaten'
}

if ([string]::IsNullOrWhiteSpace($SystemCsv)) {
    $SystemCsv = (Get-ChildItem -Path $InputFolder -Filter 'system_*.csv' -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if ([string]::IsNullOrWhiteSpace($ProcessCsv)) {
    $ProcessCsv = (Get-ChildItem -Path $InputFolder -Filter 'prozesse_*.csv' -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

if (-not $SystemCsv -or -not (Test-Path $SystemCsv)) {
    throw "Keine System-CSV gefunden. Bitte -SystemCsv angeben oder zuerst Track-Memory.ps1 laufen lassen."
}

Write-Host ("System-CSV : {0}" -f $SystemCsv)
Write-Host ("Prozess-CSV: {0}" -f $(if ($ProcessCsv) { $ProcessCsv } else { '(keine)' }))

# ---------------------------------------------------------------------------
# Daten einlesen und in Zahlen wandeln
# ---------------------------------------------------------------------------
$sys = Import-Csv -Path $SystemCsv
if (-not $sys -or $sys.Count -eq 0) { throw "Die System-CSV enthaelt keine Daten." }

# CSV-Felder sind Text -> in Double umwandeln (kultur-invariant, damit sowohl
# Punkt- als auch Komma-Dezimaltrennung korrekt gelesen wird).
function ConvertTo-Double($value) {
    if ($null -eq $value -or $value -eq '') { return 0.0 }
    $d = 0.0
    $s = ([string]$value).Replace(',', '.')
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return $d
    }
    return 0.0
}

$committed = $sys | ForEach-Object { ConvertTo-Double $_.CommittedGB }
$physInUse = $sys | ForEach-Object { ConvertTo-Double $_.PhysicalInUseGB }
$avail     = $sys | ForEach-Object { ConvertTo-Double $_.AvailableGB }
$pageReads = $sys | ForEach-Object { ConvertTo-Double $_.PageReadsPerSec }
$totalPhys = ($sys | ForEach-Object { ConvertTo-Double $_.TotalPhysicalGB } | Measure-Object -Maximum).Maximum

# ---------------------------------------------------------------------------
# Statistik-Hilfsfunktionen
# ---------------------------------------------------------------------------
function Get-Percentile {
    param([double[]]$Data, [double]$Percentile)
    if (-not $Data -or $Data.Count -eq 0) { return 0 }
    $sorted = $Data | Sort-Object
    $rank = ($Percentile / 100.0) * ($sorted.Count - 1)
    $low  = [math]::Floor($rank)
    $high = [math]::Ceiling($rank)
    if ($low -eq $high) { return [math]::Round($sorted[$low], 2) }
    $frac = $rank - $low
    return [math]::Round($sorted[$low] + ($sorted[$high] - $sorted[$low]) * $frac, 2)
}
function Stat-Max($d) { if ($d.Count) { [math]::Round(($d | Measure-Object -Maximum).Maximum, 2) } else { 0 } }
function Stat-Min($d) { if ($d.Count) { [math]::Round(($d | Measure-Object -Minimum).Minimum, 2) } else { 0 } }
function Stat-Avg($d) { if ($d.Count) { [math]::Round(($d | Measure-Object -Average).Average, 2) } else { 0 } }

$sampleCount   = $sys.Count
$firstTs       = $sys[0].Timestamp
$lastTs        = $sys[$sampleCount - 1].Timestamp

$commitMax = Stat-Max $committed
$commitP99 = Get-Percentile -Data $committed -Percentile 99
$commitP95 = Get-Percentile -Data $committed -Percentile 95
$commitP50 = Get-Percentile -Data $committed -Percentile 50
$commitAvg = Stat-Avg $committed

$physMax   = Stat-Max $physInUse
$physAvg   = Stat-Avg $physInUse
$availMin  = Stat-Min $avail
$pageMax   = Stat-Max $pageReads
$pagePressureSamples = ($pageReads | Where-Object { $_ -gt 50 }).Count
$lowAvailSamples     = ($avail     | Where-Object { $_ -lt 1 }).Count

# ---------------------------------------------------------------------------
# Empfehlungslogik
# ---------------------------------------------------------------------------
# Zielwert = massgeblicher Bedarf. Wir nehmen p99 (praktischer Spitzenbedarf,
# unempfindlich gegen einen einzelnen Ausreisser) als Grundlage und pruefen
# gegen die 80%-Schwelle der Kandidatengroessen.
$sizes = 16, 32, 64
function Recommend-Size {
    param([double]$NeedGB)
    foreach ($s in $sizes) {
        if ($NeedGB -le ($s * 0.80)) { return $s }
    }
    return 128
}
$recByP99 = Recommend-Size $commitP99
$recByMax = Recommend-Size $commitMax

# Textbaustein je nach Ergebnis
$verdict = ""
if ($recByP99 -eq $recByMax) {
    $verdict = "$recByP99 GB"
} else {
    $verdict = "$recByP99 GB (Dauerbedarf) - $recByMax GB nur fuer seltene Spitzen"
}

$pagingNote = if ($pageMax -gt 50) {
    "ACHTUNG: Es wurde nennenswerte Auslagerung gemessen (max. $pageMax Seiten/s). Selbst mit den verbauten $totalPhys GB gab es zeitweise Speicherdruck - kleinere Groessen sind riskant."
} else {
    "Keine nennenswerte Auslagerung gemessen (max. $pageMax Seiten/s) - der Testrechner hatte durchgehend genug RAM."
}

# ---------------------------------------------------------------------------
# Prozess-Auswertung: Spitzenverbrauch je Programm
# ---------------------------------------------------------------------------
$appTable = @()
if ($ProcessCsv -and (Test-Path $ProcessCsv)) {
    $proc = Import-Csv -Path $ProcessCsv
    $appTable = $proc | Group-Object ProcessName | ForEach-Object {
        $ws = $_.Group | ForEach-Object { ConvertTo-Double $_.WorkingSetGB }
        $pv = $_.Group | ForEach-Object { ConvertTo-Double $_.PrivateGB }
        [pscustomobject]@{
            Programm        = $_.Name
            SpitzeArbeitsGB = Stat-Max $ws
            MittelArbeitsGB = Stat-Avg $ws
            SpitzePrivatGB  = Stat-Max $pv
        }
    } | Sort-Object SpitzeArbeitsGB -Descending | Select-Object -First 30
}

# ---------------------------------------------------------------------------
# Konsolenausgabe
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host " AUSWERTUNG ARBEITSSPEICHER-BEDARF" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host (" Zeitraum        : {0}  bis  {1}" -f $firstTs, $lastTs)
Write-Host (" Messpunkte      : {0}" -f $sampleCount)
Write-Host (" Verbauter RAM   : {0} GB" -f $totalPhys)
Write-Host ""
Write-Host " Zugesicherter Speicher (Commit Charge) - massgeblich:" -ForegroundColor White
Write-Host ("   Maximum       : {0,6} GB" -f $commitMax)
Write-Host ("   p99           : {0,6} GB" -f $commitP99)
Write-Host ("   p95           : {0,6} GB" -f $commitP95)
Write-Host ("   Median (p50)  : {0,6} GB" -f $commitP50)
Write-Host ("   Mittelwert    : {0,6} GB" -f $commitAvg)
Write-Host ""
Write-Host (" Physisch belegt : max {0} GB / im Mittel {1} GB" -f $physMax, $physAvg)
Write-Host (" Minimal frei    : {0} GB" -f $availMin)
Write-Host (" Auslagerung     : max {0} Seiten/s" -f $pageMax)
Write-Host ""
Write-Host " EMPFEHLUNG      : $verdict" -ForegroundColor Green
Write-Host " $pagingNote"
Write-Host ""

if ($appTable.Count -gt 0) {
    Write-Host " Groesste Speicherverbraucher (Spitze):" -ForegroundColor White
    $appTable | Select-Object -First 15 |
        Format-Table Programm,
            @{n='Spitze GB'; e={'{0:N2}' -f $_.SpitzeArbeitsGB}; a='right'},
            @{n='Mittel GB'; e={'{0:N2}' -f $_.MittelArbeitsGB}; a='right'} -AutoSize
}

# ---------------------------------------------------------------------------
# HTML-Bericht
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutputHtml)) {
    $OutputHtml = Join-Path $InputFolder ("Bericht_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
}

function HtmlEncode($s) {
    return ([string]$s).Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')
}

# Empfehlungsfarbe
$recColor = switch ($recByP99) {
    16 { '#16a34a' }
    32 { '#2563eb' }
    default { '#d97706' }
}

$appRowsHtml = ""
foreach ($a in $appTable) {
    $appRowsHtml += ("<tr><td>{0}</td><td class='num'>{1:N2}</td><td class='num'>{2:N2}</td><td class='num'>{3:N2}</td></tr>`n" -f `
        (HtmlEncode $a.Programm), $a.SpitzeArbeitsGB, $a.MittelArbeitsGB, $a.SpitzePrivatGB)
}

$html = @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RAM-Bedarfsanalyse $(HtmlEncode $env:COMPUTERNAME)</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: Segoe UI, system-ui, sans-serif; margin: 0; padding: 2rem;
         background: #f8fafc; color: #0f172a; }
  @media (prefers-color-scheme: dark) { body { background:#0f172a; color:#e2e8f0; } .card{background:#1e293b!important;} th{background:#334155!important;} }
  h1 { font-size: 1.5rem; margin: 0 0 .25rem; }
  .sub { color: #64748b; margin-bottom: 1.5rem; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit,minmax(160px,1fr)); gap: 1rem; margin-bottom: 1.5rem; }
  .card { background: #fff; border-radius: 12px; padding: 1rem 1.25rem; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
  .card .label { font-size: .8rem; color: #64748b; text-transform: uppercase; letter-spacing: .03em; }
  .card .value { font-size: 1.6rem; font-weight: 700; margin-top: .25rem; }
  .rec { background: $recColor; color: #fff; border-radius: 12px; padding: 1.5rem; margin-bottom: 1.5rem; }
  .rec .big { font-size: 2.2rem; font-weight: 800; }
  table { border-collapse: collapse; width: 100%; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
  th, td { padding: .55rem .8rem; text-align: left; border-bottom: 1px solid #e2e8f0; }
  th { background: #f1f5f9; font-size: .85rem; }
  td.num { text-align: right; font-variant-numeric: tabular-nums; }
  .note { font-size: .9rem; color: #475569; margin-top: .5rem; }
  footer { margin-top: 2rem; font-size: .8rem; color: #94a3b8; }
</style>
</head>
<body>
  <h1>Arbeitsspeicher-Bedarfsanalyse</h1>
  <div class="sub">Rechner <b>$(HtmlEncode $env:COMPUTERNAME)</b> &middot; $(HtmlEncode $firstTs) bis $(HtmlEncode $lastTs) &middot; $sampleCount Messpunkte &middot; verbauter RAM: $totalPhys GB</div>

  <div class="rec">
    <div class="label" style="opacity:.85">Empfehlung</div>
    <div class="big">$verdict</div>
    <div class="note" style="color:#f8fafc;opacity:.95">$(HtmlEncode $pagingNote)</div>
  </div>

  <div class="grid">
    <div class="card"><div class="label">Commit &ndash; Maximum</div><div class="value">$commitMax GB</div></div>
    <div class="card"><div class="label">Commit &ndash; p99</div><div class="value">$commitP99 GB</div></div>
    <div class="card"><div class="label">Commit &ndash; p95</div><div class="value">$commitP95 GB</div></div>
    <div class="card"><div class="label">Commit &ndash; Median</div><div class="value">$commitP50 GB</div></div>
    <div class="card"><div class="label">Physisch belegt (max)</div><div class="value">$physMax GB</div></div>
    <div class="card"><div class="label">Minimal frei</div><div class="value">$availMin GB</div></div>
    <div class="card"><div class="label">Auslagerung (max)</div><div class="value">$pageMax /s</div></div>
  </div>

  <p class="note"><b>Lesehilfe:</b> Massgeblich ist der <b>zugesicherte Speicher (Commit Charge)</b> &ndash; die Menge, die alle Programme zusammen angefordert haben. Sie ist unabhaengig vom verbauten RAM und damit die belastbare Groesse fuer die Beschaffung. Eine Speichergroesse gilt als komfortabel, wenn der Bedarf rund 80&nbsp;% davon nicht ueberschreitet (Rest = Reserve fuer Spitzen und Datei-Cache).</p>

  <h2 style="font-size:1.2rem;margin-top:1.5rem">Groesste Speicherverbraucher</h2>
  <table>
    <thead><tr><th>Programm</th><th class="num">Spitze Arbeitsspeicher (GB)</th><th class="num">Mittel (GB)</th><th class="num">Spitze privat (GB)</th></tr></thead>
    <tbody>
$appRowsHtml
    </tbody>
  </table>

  <footer>Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') mit Track-Memory.ps1 / Analyze-Memory.ps1</footer>
</body>
</html>
"@

$html | Out-File -FilePath $OutputHtml -Encoding UTF8
Write-Host (" HTML-Bericht    : {0}" -f $OutputHtml) -ForegroundColor Green
Write-Host "===================================================================" -ForegroundColor Cyan
