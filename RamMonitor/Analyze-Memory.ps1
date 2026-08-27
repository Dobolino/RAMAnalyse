<#
.SYNOPSIS
    Wertet die von Track-Memory.ps1 erzeugten CSV-Dateien aus und erzeugt einen
    laienverstaendlichen HTML-Bericht mit RAM-Empfehlung (16 / 32 / 64 GB).

.BESCHREIBUNG
    Standardmaessig werden ALLE Messungen im Datenordner zusammen ausgewertet
    (z. B. fuenf Messtage -> ein Gesamtergebnis). Man kann mit -SystemCsv auch
    gezielt eine einzelne Datei auswerten.

    Methodik (siehe Glossar im Bericht):
      * Leitgroesse ist der zugesicherte Speicher (Commit Charge).
      * Gegenprobe: physisch genutzter Speicher ohne Datei-Cache.
      * Empfehlung = das Maximum aus beiden Wegen, mit Reserve.
      * Auslagerung zaehlt nur dann als Speichermangel, wenn GLEICHZEITIG wenig
        RAM frei war (verhindert Fehlalarme durch normales Nachladen).

.PARAMETER SystemCsv
    Genau eine system_*.csv auswerten (statt aller). Optional.
.PARAMETER ProcessCsv
    Passende prozesse_*.csv zu -SystemCsv. Optional (wird sonst abgeleitet).
.PARAMETER InputFolder
    Ordner mit den CSV-Dateien. Standard: Unterordner "Messdaten" neben dem Skript.
.PARAMETER Machine
    Nur Messungen dieses Rechners auswerten (bei mehreren Test-PCs im Ordner).
.PARAMETER OutputHtml
    Zielpfad des HTML-Berichts. Standard: Bericht_<Zeitstempel>.html im Ordner.

.BEISPIEL
    .\Analyze-Memory.ps1
    Wertet alle Messtage im Ordner "Messdaten" aus.
#>

[CmdletBinding()]
param(
    [string]$SystemCsv,
    [string]$ProcessCsv,
    [string]$InputFolder,
    [string]$Machine,
    [string]$OutputHtml,
    [ValidateSet('IT','Einfach','Beide')]
    [string]$Zielgruppe = 'Beide'
)

$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# ===========================================================================
# Hilfsfunktionen
# ===========================================================================
function ConvertTo-Double($value) {
    if ($null -eq $value -or $value -eq '') { return 0.0 }
    $d = 0.0
    $s = ([string]$value).Replace(',', '.')
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Any, $inv, [ref]$d)) { return $d }
    return 0.0
}
function Fmt([double]$v, [int]$dec = 2) { return $v.ToString('N' + $dec, $inv) }

function Get-Percentile {
    param([double[]]$Data, [double]$Percentile)
    if (-not $Data -or $Data.Count -eq 0) { return 0 }
    $sorted = @($Data | Sort-Object)
    if ($sorted.Count -eq 1) { return [math]::Round($sorted[0], 2) }
    $rank = ($Percentile / 100.0) * ($sorted.Count - 1)
    $low  = [int][math]::Floor($rank)
    $high = [int][math]::Ceiling($rank)
    if ($low -eq $high) { return [math]::Round($sorted[$low], 2) }
    $frac = $rank - $low
    return [math]::Round($sorted[$low] + ($sorted[$high] - $sorted[$low]) * $frac, 2)
}
function Stat-Max($d) { if ($d -and @($d).Count) { [math]::Round((@($d) | Measure-Object -Maximum).Maximum, 2) } else { 0 } }
function Stat-Min($d) { if ($d -and @($d).Count) { [math]::Round((@($d) | Measure-Object -Minimum).Minimum, 2) } else { 0 } }
function Stat-Avg($d) { if ($d -and @($d).Count) { [math]::Round((@($d) | Measure-Object -Average).Average, 2) } else { 0 } }
function HtmlEncode($s) { return ([string]$s).Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;') }

function Parse-Ts([string]$s) {
    $dt = [datetime]::MinValue
    if ([datetime]::TryParseExact($s, 'yyyy-MM-dd HH:mm:ss', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { return $dt }
    if ([datetime]::TryParse($s, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { return $dt }
    return $null
}

# ===========================================================================
# Eingabedateien bestimmen
# ===========================================================================
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($InputFolder)) { $InputFolder = Join-Path $scriptDir 'Messdaten' }

# Liste der auszuwertenden System-CSVs (je Eintrag: System- + zugehoerige Prozess-CSV)
$systemFiles = @()
if (-not [string]::IsNullOrWhiteSpace($SystemCsv)) {
    if (-not (Test-Path $SystemCsv)) { throw "Angegebene System-CSV nicht gefunden: $SystemCsv" }
    $systemFiles = @($SystemCsv)
} else {
    $systemFiles = @(Get-ChildItem -Path $InputFolder -Filter 'system_*.csv' -ErrorAction SilentlyContinue |
                     Sort-Object Name | Select-Object -ExpandProperty FullName)
}
if (-not $systemFiles -or $systemFiles.Count -eq 0) {
    throw "Keine System-CSV gefunden in '$InputFolder'. Bitte zuerst Track-Memory.ps1 laufen lassen."
}

# ===========================================================================
# Runs einlesen
# ===========================================================================
function Get-MachineFromFile([string]$sysFile, $firstRow) {
    if ($firstRow -and $firstRow.PSObject.Properties.Name -contains 'Machine' -and $firstRow.Machine) {
        return [string]$firstRow.Machine
    }
    # Fallback: aus Dateinamen  system_<MACHINE>_<datum...>.csv
    $base = [System.IO.Path]::GetFileNameWithoutExtension($sysFile)
    $base = $base -replace '^system_', ''
    return ($base -split '_')[0]
}

$runs = @()
foreach ($sf in $systemFiles) {
    $rows = @(Import-Csv -Path $sf)
    if (-not $rows -or $rows.Count -eq 0) { continue }

    $mach = Get-MachineFromFile $sf $rows[0]

    # Passende Prozess-CSV finden
    $pf = $null
    if (-not [string]::IsNullOrWhiteSpace($ProcessCsv) -and (Test-Path $ProcessCsv)) {
        $pf = $ProcessCsv
    } else {
        $cand = $sf -replace 'system_', 'prozesse_'
        if (Test-Path $cand) { $pf = $cand }
    }
    $prows = @()
    if ($pf) { $prows = @(Import-Csv -Path $pf) }

    $starts = Parse-Ts $rows[0].Timestamp
    $ends   = Parse-Ts $rows[$rows.Count - 1].Timestamp

    $runs += [pscustomobject]@{
        SystemFile  = $sf
        ProcessFile = $pf
        Machine     = $mach
        Rows        = $rows
        ProcRows    = $prows
        Start       = $starts
        End         = $ends
        Samples     = $rows.Count
    }
}
if ($runs.Count -eq 0) { throw "Die gefundenen CSV-Dateien enthalten keine Daten." }

# Mehrere Rechner? -> auf einen einschraenken (sonst waere die Aggregation falsch).
$machines = @($runs | Select-Object -ExpandProperty Machine -Unique)
$ignoredMachines = @()
if (-not [string]::IsNullOrWhiteSpace($Machine)) {
    $selMachine = $Machine
} elseif ($machines.Count -eq 1) {
    $selMachine = $machines[0]
} else {
    # Rechner mit den meisten Messpunkten waehlen
    $selMachine = ($runs | Group-Object Machine |
                   Sort-Object { ($_.Group | Measure-Object Samples -Sum).Sum } -Descending |
                   Select-Object -First 1).Name
    $ignoredMachines = @($machines | Where-Object { $_ -ne $selMachine })
}
$runs = @($runs | Where-Object { $_.Machine -eq $selMachine })
if ($runs.Count -eq 0) { throw "Keine Messungen fuer Rechner '$selMachine' gefunden." }

# ===========================================================================
# Kombinierte Kennzahlen ueber ALLE Runs
# ===========================================================================
$committed = New-Object System.Collections.Generic.List[double]
$physInUse = New-Object System.Collections.Generic.List[double]
$physNet   = New-Object System.Collections.Generic.List[double]   # physisch genutzt OHNE Cache
$avail     = New-Object System.Collections.Generic.List[double]
$pageReads = New-Object System.Collections.Generic.List[double]
$totalPhys = 0.0
$peakCommit = -1.0; $peakRun = $null; $peakTs = $null

foreach ($r in $runs) {
    foreach ($row in $r.Rows) {
        $c  = ConvertTo-Double $row.CommittedGB
        $pu = ConvertTo-Double $row.PhysicalInUseGB
        $ca = ConvertTo-Double $row.CacheGB
        $av = ConvertTo-Double $row.AvailableGB
        $pr = ConvertTo-Double $row.PageReadsPerSec
        $tp = ConvertTo-Double $row.TotalPhysicalGB
        $committed.Add($c); $physInUse.Add($pu); $avail.Add($av); $pageReads.Add($pr)
        $net = $pu - $ca; if ($net -lt 0) { $net = 0 }
        $physNet.Add($net)
        if ($tp -gt $totalPhys) { $totalPhys = $tp }
        if ($c -gt $peakCommit) { $peakCommit = $c; $peakRun = $r; $peakTs = $row.Timestamp }
    }
}

$sampleCount = $committed.Count
$commitMax = Stat-Max $committed
$commitP99 = Get-Percentile -Data $committed.ToArray() -Percentile 99
$commitP95 = Get-Percentile -Data $committed.ToArray() -Percentile 95
$commitP50 = Get-Percentile -Data $committed.ToArray() -Percentile 50
$commitAvg = Stat-Avg $committed

$physMax    = Stat-Max $physInUse
$physNetP99 = Get-Percentile -Data $physNet.ToArray() -Percentile 99
$physNetMax = Stat-Max $physNet
$availMin   = Stat-Min $avail
$pageMax    = Stat-Max $pageReads

# Gesamtdauer + Messtage
$spanMinutes = 0.0
$days = @()
foreach ($r in $runs) {
    if ($r.Start -and $r.End) { $spanMinutes += ($r.End - $r.Start).TotalMinutes }
    if ($r.Start) { $days += $r.Start.ToString('yyyy-MM-dd') }
}
$dayCount = @($days | Select-Object -Unique).Count
$spanText = if ($spanMinutes -ge 120) { "{0} h" -f (Fmt ($spanMinutes/60) 1) } else { "{0} min" -f ([int]$spanMinutes) }

# ---------------------------------------------------------------------------
# B1: Auslagerung nur mit wenig-frei koppeln
# ---------------------------------------------------------------------------
$lowAvailGB = [math]::Max(1.0, [math]::Round($totalPhys * 0.05, 1))
$pressureSamples = 0
for ($i = 0; $i -lt $sampleCount; $i++) {
    if ($pageReads[$i] -gt 50 -and $avail[$i] -lt $lowAvailGB) { $pressureSamples++ }
}

# ---------------------------------------------------------------------------
# B3: Bedarf = max(Commit-Weg, Physisch-ohne-Cache-Weg)
# ---------------------------------------------------------------------------
$needP99 = [math]::Max($commitP99, $physNetP99)
$needMax = [math]::Max($commitMax, $physNetMax)

# ---------------------------------------------------------------------------
# Ampel-Bewertung je Groesse
# ---------------------------------------------------------------------------
function Get-Verdict {
    param([double]$Need, [double]$Size)
    $r = if ($Size -gt 0) { $Need / $Size } else { 9 }
    if     ($r -le 0.75) { return [pscustomobject]@{ Label='Komfortabel'; Color='#16a34a'; Ratio=$r } }
    elseif ($r -le 0.90) { return [pscustomobject]@{ Label='Ausreichend'; Color='#65a30d'; Ratio=$r } }
    elseif ($r -le 1.02) { return [pscustomobject]@{ Label='Grenzwertig'; Color='#d97706'; Ratio=$r } }
    else                 { return [pscustomobject]@{ Label='Zu klein';    Color='#dc2626'; Ratio=$r } }
}
# Ampel und Kopf-Empfehlung nutzen DIESELBE Basis (Commit p95), damit die
# markierte Empfehlung nie einer rot bewerteten Zeile widerspricht. Der
# physische Bedarf ist die Gegenprobe (Zwei-Faktor-Logik + Realitaets-Check).
$sizes = 16, 32, 64
$verdicts = foreach ($s in $sizes) {
    $v = Get-Verdict -Need $commitP95 -Size $s
    [pscustomobject]@{ Size=$s; Label=$v.Label; Color=$v.Color; Ratio=$v.Ratio }
}
# ---------------------------------------------------------------------------
# ZWEI-FAKTOR-EMPFEHLUNG (verhindert Fehlkaeufe durch reservierten, aber nicht
# genutzten Commit-Speicher):
#   Eine groessere RAM-Klasse wird nur empfohlen, wenn SOWOHL der zugesicherte
#   Speicher (Commit p95) ALS AUCH der tatsaechlich physisch belegte Speicher
#   (Working Set / physisch ohne Cache, Max) hoch sind. Grund: Ein 64-GB-
#   Testsystem gewaehrt Anwendungen (v. a. Browser, Electron-Apps wie Teams)
#   mehr Speicher, als sie auf einem 32-GB-System aktiv belegen wuerden - dort
#   greifen frueher Memory Pressure / Garbage Collection. Commit allein wuerde
#   daher tendenziell zu gross dimensionieren.
# ---------------------------------------------------------------------------
# Physische Schwellen je Klasse (Working-Set-Max muss diese ueberschreiten,
# damit die Klasse allein durch Commit nicht "hochgezogen" wird):
$wsGate32 = 12.0   # fuer 16 -> 32
$wsGate64 = 22.0   # fuer 32 -> 64  (wie im Prüfauftrag gefordert)

$recSize = 16
# 16 -> 32
if ($commitP95 -gt (16 * 0.8) -and $physNetMax -gt $wsGate32) { $recSize = 32 }
# Sicherheits-Override: Commit passt physisch gar nicht mehr in 16 GB
if ($commitP95 -gt 16) { $recSize = [math]::Max($recSize, 32) }
# 32 -> 64: BEIDE Bedingungen noetig (Commit p95 > 25.6 UND Working Set > 22)
if ($commitP95 -gt (32 * 0.8) -and $physNetMax -gt $wsGate64) { $recSize = 64 }
# Sicherheits-Override: Commit uebersteigt 32 GB komplett -> 64 unvermeidbar
if ($commitP95 -gt 32) { $recSize = [math]::Max($recSize, 64) }
# darueber
if ($commitP95 -gt 64) { $recSize = 128 }

$recVerdict = Get-Verdict -Need $commitP95 -Size $recSize
$recColor = if ($recSize -le 64) { $recVerdict.Color } else { '#dc2626' }

# Divergenz erkennen: Commit wuerde eine groessere Klasse nahelegen, physisch
# ist der Bedarf aber deutlich kleiner (reservierter, ungenutzter Speicher).
$commitOnlySize = 16
if ($commitP95 -gt (16 * 0.8) -or $commitP95 -gt 16) { $commitOnlySize = 32 }
if ($commitP95 -gt (32 * 0.8) -or $commitP95 -gt 32) { $commitOnlySize = 64 }
if ($commitP95 -gt 64) { $commitOnlySize = 128 }
$commitPhysGap = ($commitOnlySize -gt $recSize)

# Klartext-Empfehlung
$plain = "Empfohlen werden $recSize GB Arbeitsspeicher fuer diesen Arbeitsplatz-Typ."
if ($commitPhysGap) {
    $plain += " Der zugesicherte Speicher (Commit) wuerde rechnerisch $commitOnlySize GB nahelegen, doch physisch belegt wurden maximal nur $(Fmt $physNetMax) GB. Die Differenz ist reservierter, aber nicht aktiv genutzter Speicher (typisch fuer Browser/Teams auf einem grossen Testgeraet) - auf einem $recSize-GB-System faellt dieser Reservespeicher kleiner aus. $recSize GB genuegen daher voraussichtlich."
} elseif ($recSize -ge 64 -and $commitP95 -gt 64) {
    $plain += " Der gemessene Bedarf uebersteigt 64 GB - hier ist mehr noetig."
} else {
    $plain += " Sowohl der zugesicherte als auch der physisch genutzte Speicher stuetzen diese Groesse."
}

# ---------------------------------------------------------------------------
# Konfidenz (Aussagekraft der Messung)
# ---------------------------------------------------------------------------
$confLevel = 'gut'; $confText = ''
if ($sampleCount -lt 60 -or $spanMinutes -lt 60) {
    $confLevel = 'gering'
    $confText = "Diese Messung ist noch NICHT aussagekraeftig: nur $sampleCount Messpunkte ueber rund $spanText (Richtwert: mindestens 60 Messpunkte bzw. 1 Stunde). Bei so wenigen Messpunkten ist der p99-Wert praktisch identisch mit dem Maximum - ein einzelner Ausreisser bestimmt dann die Empfehlung. Fuer eine belastbare Beschaffungsentscheidung bitte ueber mindestens einen vollen Arbeitstag messen - idealerweise mehrere Tage - und dabei die typische Last laufen lassen (mehrere CAD-Projekte, Videokonferenz, Browser gleichzeitig)."
} elseif ($spanMinutes -lt 480 -or $dayCount -lt 2) {
    $confLevel = 'mittel'
    $confText = "Grundlage: $sampleCount Messpunkte ueber rund $spanText an $dayCount Tag(en). Fuer mehr Sicherheit ueber mehrere volle Arbeitstage messen."
} else {
    $confText = "Solide Grundlage: $sampleCount Messpunkte ueber rund $spanText an $dayCount Messtagen."
}

# ---------------------------------------------------------------------------
# Auslagerungs-Hinweis (B1)
# ---------------------------------------------------------------------------
$pagingNote = if ($pressureSamples -gt 0) {
    "In $pressureSamples Messpunkt(en) gab es echten Speicherdruck (Nachladen von der Platte bei gleichzeitig wenig freiem RAM). Selbst mit den verbauten $(Fmt $totalPhys) GB wurde es zeitweise eng - kleinere Groessen sind riskant."
} else {
    "Kein echter Speicherdruck gemessen (kein Nachladen bei knappem RAM). Der Testrechner hatte durchgehend genug Arbeitsspeicher."
}

# ---------------------------------------------------------------------------
# Prozess-Auswertung (Spitzenverbrauch je Programm) ueber alle Runs
# ---------------------------------------------------------------------------
$allProc = New-Object System.Collections.Generic.List[object]
foreach ($r in $runs) { foreach ($pr in $r.ProcRows) { $allProc.Add($pr) } }

$appTable = @()
if ($allProc.Count -gt 0) {
    $appTable = $allProc | Group-Object ProcessName | ForEach-Object {
        $ws = $_.Group | ForEach-Object { ConvertTo-Double $_.WorkingSetGB }
        $pv = $_.Group | ForEach-Object { ConvertTo-Double $_.PrivateGB }
        [pscustomobject]@{
            Programm        = $_.Name
            SpitzePrivatGB  = Stat-Max $pv
            MittelPrivatGB  = Stat-Avg $pv
            SpitzeArbeitsGB = Stat-Max $ws
        }
    } | Sort-Object SpitzePrivatGB -Descending | Select-Object -First 30
}

# ---------------------------------------------------------------------------
# "Was lief beim Hoechststand?" - Prozesse zum Zeitpunkt des Commit-Maximums
# ---------------------------------------------------------------------------
$peakProc = @()
if ($peakRun -and $peakRun.ProcRows.Count -gt 0 -and $peakTs) {
    $peakProc = @($peakRun.ProcRows | Where-Object { $_.Timestamp -eq $peakTs } |
        ForEach-Object {
            [pscustomobject]@{
                Programm  = $_.ProcessName
                PrivatGB  = ConvertTo-Double $_.PrivateGB
                ArbeitsGB = ConvertTo-Double $_.WorkingSetGB
            }
        } | Sort-Object PrivatGB -Descending | Select-Object -First 15)
}

# ===========================================================================
# Konsolenausgabe (Kurzfassung)
# ===========================================================================
Write-Host ""
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host " AUSWERTUNG ARBEITSSPEICHER-BEDARF" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host (" Rechner        : {0}" -f $selMachine)
Write-Host (" Messtage/Laeufe: {0} Tag(e) / {1} Lauf(e)" -f $dayCount, $runs.Count)
Write-Host (" Messpunkte     : {0}  (ueber rund {1})" -f $sampleCount, $spanText)
Write-Host (" Verbauter RAM  : {0} GB" -f (Fmt $totalPhys))
if ($ignoredMachines.Count -gt 0) {
    Write-Host (" Hinweis        : Weitere Rechner im Ordner ignoriert: {0}" -f ($ignoredMachines -join ', ')) -ForegroundColor Yellow
}
Write-Host ""
Write-Host " Bedarf (Commit / physisch, massgeblich der groessere Wert):" -ForegroundColor White
Write-Host ("   Spitze (Max)  : {0,6} GB" -f (Fmt $needMax))
Write-Host ("   Dauerbedarf p99: {0,5} GB" -f (Fmt $needP99))
Write-Host ""
foreach ($v in $verdicts) {
    $col = switch ($v.Label) { 'Komfortabel' {'Green'} 'Ausreichend' {'Green'} 'Grenzwertig' {'Yellow'} default {'Red'} }
    Write-Host ("   {0,3} GB -> {1,-12} (Auslastung {2}%)" -f $v.Size, $v.Label, [int]([math]::Round($v.Ratio*100))) -ForegroundColor $col
}
Write-Host ""
Write-Host (" EMPFEHLUNG     : {0} GB" -f $recSize) -ForegroundColor Green
if ($confLevel -eq 'gering') { Write-Host (" ! {0}" -f $confText) -ForegroundColor Red }
Write-Host ""

# ===========================================================================
# HTML-Berichte aufbauen (Detail fuer IT + einfacher Ein-Seiter)
# ===========================================================================

# --- Fragment: Konfidenz-Banner ---
$confColor = switch ($confLevel) { 'gering' {'#dc2626'} 'mittel' {'#d97706'} default {'#16a34a'} }
$confTitle = switch ($confLevel) { 'gering' {'Achtung - Messung zu kurz'} 'mittel' {'Hinweis zur Aussagekraft'} default {'Aussagekraft'} }
$confidenceHtml = "<div class='banner' style='background:$confColor'><div class='banner-t'>$(HtmlEncode $confTitle)</div><div>$(HtmlEncode $confText)</div></div>"

# --- Fragment: Verlaufs-Diagramm (Inline-SVG, Commit ueber die Zeit) ---
$chartHtml = ""
if ($sampleCount -ge 2) {
    $W = 900; $H = 240; $padL = 48; $padR = 16; $padT = 14; $padB = 24
    $vals = $committed.ToArray()
    $yMax = [math]::Max($totalPhys, ($commitMax * 1.05))
    if ($yMax -le 0) { $yMax = 16 }
    $n = $vals.Count
    $plotW = $W - $padL - $padR
    $plotH = $H - $padT - $padB
    $pts = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $n; $i++) {
        $x = $padL + [int]([double]$i / [math]::Max(1, ($n - 1)) * $plotW)
        $y = $padT + [int]((1 - ([double]$vals[$i] / $yMax)) * $plotH)
        [void]$pts.Append("$x,$y ")
    }
    $areaPts = "$padL,$($padT + $plotH) " + $pts.ToString() + "$($padL + $plotW),$($padT + $plotH)"

    # Referenzlinien 16/32/64 GB + verbauter RAM
    $refHtml = ""
    $refs = @(
        @{ v = 16; c = '#16a34a'; t = '16 GB' },
        @{ v = 32; c = '#d97706'; t = '32 GB' },
        @{ v = 64; c = '#dc2626'; t = '64 GB' }
    )
    foreach ($rf in $refs) {
        if ($rf.v -le $yMax) {
            $ry = $padT + [int]((1 - ([double]$rf.v / $yMax)) * $plotH)
            $refHtml += "<line x1='$padL' y1='$ry' x2='$($padL + $plotW)' y2='$ry' stroke='$($rf.c)' stroke-width='1' stroke-dasharray='5 4' opacity='.75'/>"
            $refHtml += "<text x='6' y='$($ry + 4)' font-size='11' fill='$($rf.c)'>$($rf.t)</text>"
        }
    }
    $chartHtml = @"
<h2>Verlauf des Speicherbedarfs <span class="info" title="Die blaue Linie ist der zugesicherte Speicher ueber die Messzeit. Bleibt sie unter der 32-GB-Linie, reichen 32 GB; kratzt sie an einer Linie, wird diese Groesse knapp.">?</span></h2>
<p class="muted">Blaue Linie = zugesicherter Speicher (Commit). Gestrichelt = die RAM-Groessen zum Vergleich. Alle Messtage sind aneinandergereiht.</p>
<div class="tablewrap"><svg viewBox="0 0 $W $H" width="100%" preserveAspectRatio="xMidYMid meet" role="img" aria-label="Verlauf des zugesicherten Speichers">
  <polygon points="$areaPts" fill="#3b82f6" opacity="0.12"/>
  $refHtml
  <polyline points="$($pts.ToString().Trim())" fill="none" stroke="#3b82f6" stroke-width="2"/>
  <text x="6" y="12" font-size="11" fill="currentColor" opacity=".6">GB</text>
</svg></div>
"@
}

# --- Fragment: Ampel-Tabelle der Groessen ---
$sizeRowsHtml = ""
foreach ($v in $verdicts) {
    $pct = [int]([math]::Round($v.Ratio * 100))
    $barPct = [math]::Min($pct, 100)
    $isRec = ($v.Size -eq $recSize)
    $star = if ($isRec) { " &#9733;" } else { "" }
    $sizeRowsHtml += @"
<tr$(if($isRec){" class='rec-row'"})>
  <td class='sz'>$($v.Size) GB$star</td>
  <td class='barcell'><div class='bar'><div class='barfill' style='width:$barPct%;background:$($v.Color)'></div></div></td>
  <td class='pct'>$pct&nbsp;%</td>
  <td><span class='pill' style='background:$($v.Color)'>$($v.Label)</span></td>
</tr>
"@
}

# --- Fragment: Aufschluesselung pro Messtag/Lauf ---
$runRowsHtml = ""
foreach ($r in ($runs | Sort-Object Start)) {
    $rc = @($r.Rows | ForEach-Object { ConvertTo-Double $_.CommittedGB })
    $rMax = Stat-Max $rc
    $rP99 = Get-Percentile -Data $rc -Percentile 99
    $zeit = if ($r.Start -and $r.End) { "{0} - {1}" -f $r.Start.ToString('dd.MM. HH:mm'), $r.End.ToString('HH:mm') } else { "?" }
    $dur  = if ($r.Start -and $r.End) { [int]($r.End - $r.Start).TotalMinutes } else { 0 }
    $runRowsHtml += "<tr><td>$(HtmlEncode $zeit)</td><td class='num'>$($r.Samples)</td><td class='num'>$dur min</td><td class='num'>$(Fmt $rMax) GB</td><td class='num'>$(Fmt $rP99) GB</td></tr>`n"
}

# --- Fragment: Top-Verbraucher ---
$appRowsHtml = ""
foreach ($a in $appTable) {
    $appRowsHtml += "<tr><td>$(HtmlEncode $a.Programm)</td><td class='num'>$(Fmt $a.SpitzePrivatGB)</td><td class='num'>$(Fmt $a.MittelPrivatGB)</td><td class='num'>$(Fmt $a.SpitzeArbeitsGB)</td></tr>`n"
}

# --- Fragment: Hoechststand-Snapshot ---
$peakHtml = ""
if ($peakProc.Count -gt 0) {
    $peakRows = ""
    foreach ($p in $peakProc) {
        $peakRows += "<tr><td>$(HtmlEncode $p.Programm)</td><td class='num'>$(Fmt $p.PrivatGB)</td><td class='num'>$(Fmt $p.ArbeitsGB)</td></tr>`n"
    }
    $peakHtml = @"
<h2>Was lief beim Hoechststand?</h2>
<p class='muted'>Groesster gemessener Bedarf am <b>$(HtmlEncode $peakTs)</b> mit <b>$(Fmt $peakCommit) GB</b> zugesichertem Speicher. Diese Programme waren dann offen (nach privatem Speicher sortiert):</p>
<div class='tablewrap'><table>
<thead><tr><th>Programm</th><th class='num'>Privat (GB)</th><th class='num'>Arbeitsspeicher (GB)</th></tr></thead>
<tbody>
$peakRows
</tbody></table></div>
"@
}

$ignoredHtml = ""
if ($ignoredMachines.Count -gt 0) {
    $ignoredHtml = "<p class='muted'>Hinweis: Der Ordner enthaelt auch Messungen anderer Rechner ($(HtmlEncode ($ignoredMachines -join ', '))). Dieser Bericht wertet nur <b>$(HtmlEncode $selMachine)</b> aus. Fuer die anderen Rechner mit <code>-Machine NAME</code> eigene Berichte erstellen.</p>"
}

$html = @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RAM-Bedarfsanalyse $(HtmlEncode $selMachine)</title>
<style>
  :root { --bg:#f4f6fb; --fg:#0f172a; --muted:#64748b; --card:#ffffff; --line:#e2e8f0; --th:#f1f5f9; }
  @media (prefers-color-scheme: dark) { :root { --bg:#0b1220; --fg:#e2e8f0; --muted:#94a3b8; --card:#1e293b; --line:#334155; --th:#334155; } }
  * { box-sizing: border-box; }
  body { font-family: "Segoe UI", system-ui, sans-serif; margin:0; padding:2rem 1.5rem; background:var(--bg); color:var(--fg); line-height:1.5; }
  .wrap { max-width: 980px; margin: 0 auto; }
  h1 { font-size:1.6rem; margin:0 0 .2rem; }
  h2 { font-size:1.2rem; margin:2rem 0 .6rem; }
  .sub { color:var(--muted); margin-bottom:1.4rem; font-size:.95rem; }
  .muted { color:var(--muted); font-size:.92rem; }
  .banner { color:#fff; border-radius:12px; padding:1rem 1.2rem; margin-bottom:1.2rem; }
  .banner-t { font-weight:700; margin-bottom:.2rem; }
  .rec { border-radius:14px; padding:1.4rem 1.5rem; margin-bottom:1.4rem; color:#fff; background:$recColor; }
  .rec .k { font-size:.8rem; text-transform:uppercase; letter-spacing:.04em; opacity:.9; }
  .rec .v { font-size:2.6rem; font-weight:800; line-height:1.1; margin:.1rem 0 .4rem; }
  .rec .p { font-size:1rem; opacity:.97; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:1rem 1.2rem; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:.8rem; margin:.4rem 0 0; }
  .tile .lbl { font-size:.72rem; text-transform:uppercase; letter-spacing:.03em; color:var(--muted); display:flex; align-items:center; gap:.3rem; }
  .tile .val { font-size:1.5rem; font-weight:700; margin-top:.15rem; }
  .tile .hint { font-size:.78rem; color:var(--muted); margin-top:.25rem; }
  table { border-collapse:collapse; width:100%; background:var(--card); border:1px solid var(--line); border-radius:12px; overflow:hidden; }
  .tablewrap { overflow-x:auto; }
  th,td { padding:.55rem .8rem; text-align:left; border-bottom:1px solid var(--line); font-size:.92rem; color:var(--fg); }
  th { background:var(--th); color:var(--fg); }
  tbody tr:nth-child(even) td { background:rgba(148,163,184,.10); }
  tbody tr:hover td { background:rgba(59,130,246,.14); }
  @media (prefers-color-scheme: dark) {
    td, th { color:#e2e8f0; }
    tbody tr:nth-child(even) td { background:rgba(226,232,240,.06); }
  }
  td.num, th.num { text-align:right; font-variant-numeric:tabular-nums; }
  .sizetable td { vertical-align:middle; }
  .sz { font-weight:700; white-space:nowrap; }
  .rec-row { outline:2px solid $recColor; }
  .bar { background:var(--line); border-radius:6px; height:14px; width:100%; min-width:120px; overflow:hidden; }
  .barfill { height:100%; }
  .pct { text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap; }
  .pill { color:#fff; padding:.15rem .6rem; border-radius:999px; font-size:.8rem; font-weight:600; white-space:nowrap; }
  .info { display:inline-flex; align-items:center; justify-content:center; width:15px; height:15px; border-radius:50%; background:var(--muted); color:var(--card); font-size:.7rem; font-weight:700; cursor:help; }
  details { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:.6rem 1rem; margin:.5rem 0; }
  summary { cursor:pointer; font-weight:600; }
  .gloss { margin:.6rem 0; padding:.6rem .2rem; border-bottom:1px dashed var(--line); }
  .gloss:last-child { border-bottom:0; }
  .gloss b { display:block; }
  .good { color:#16a34a; } .warn { color:#d97706; } .bad { color:#dc2626; }
  footer { margin-top:2rem; font-size:.8rem; color:var(--muted); }
</style>
</head>
<body>
<div class="wrap">

  <h1>Arbeitsspeicher-Bedarfsanalyse</h1>
  <div class="sub">Rechner <b>$(HtmlEncode $selMachine)</b> &middot; $dayCount Messtag(e), $($runs.Count) Lauf(e), $sampleCount Messpunkte &middot; verbauter RAM: $(Fmt $totalPhys) GB</div>

  $confidenceHtml

  <div class="rec">
    <div class="k">Empfehlung</div>
    <div class="v">$recSize GB</div>
    <div class="p">$(HtmlEncode $plain)</div>
  </div>

  <h2>Reicht welche Groesse? <span class="info" title="Auslastung = benoetigter Speicher geteilt durch die Groesse. Unter 75% = viel Reserve, bis 90% = ok, bis ca. 100% = knapp, darueber = zu klein.">?</span></h2>
  <p class="muted">Bewertet anhand des <b>zugesicherten Speichers (Commit p95)</b> von <b>$(Fmt $commitP95) GB</b>. Gruen = komfortabel, Gelb/Orange = knapp, Rot = zu klein. &#9733; = Empfehlung.</p>
  <p class="muted"><b>Realitaets-Check:</b> Zugesichert (Commit p95) = $(Fmt $commitP95) GB &middot; tatsaechlich physisch belegt (max, ohne Cache) = $(Fmt $physNetMax) GB. Die Empfehlung stuft nur dann hoch, wenn <b>beide</b> Werte hoch sind - reservierter, aber ungenutzter Speicher fuehrt so nicht zu einem Fehlkauf.</p>
  <div class="tablewrap"><table class="sizetable">
    <thead><tr><th>Groesse</th><th>Auslastung</th><th class="num">%</th><th>Bewertung</th></tr></thead>
    <tbody>
$sizeRowsHtml
    </tbody>
  </table></div>

  $chartHtml

  <h2>Die wichtigsten Zahlen</h2>
  <div class="grid">
    <div class="card tile"><div class="lbl">Bedarf Dauer (p99) <span class="info" title="Der Wert, den 99% aller Messungen nicht ueberschritten haben - der praktische Spitzenbedarf ohne einzelne Ausreisser. Das ist die wichtigste Zahl fuer die Beschaffung.">?</span></div><div class="val">$(Fmt $needP99) GB</div><div class="hint">massgeblich fuer die Empfehlung</div></div>
    <div class="card tile"><div class="lbl">Bedarf Spitze (Max) <span class="info" title="Der hoechste einzelne Messwert. Zeigt den absoluten Worst-Case, kann ein kurzer Ausreisser sein.">?</span></div><div class="val">$(Fmt $needMax) GB</div><div class="hint">hoechster Einzelwert</div></div>
    <div class="card tile"><div class="lbl">Commit p99 <span class="info" title="Zugesicherter Speicher: die Menge, die alle Programme zusammen angefordert haben. Unabhaengig vom verbauten RAM.">?</span></div><div class="val">$(Fmt $commitP99) GB</div><div class="hint">angeforderter Speicher</div></div>
    <div class="card tile"><div class="lbl">Physisch genutzt <span class="info" title="Tatsaechlich mit Daten belegter RAM ohne den Datei-Cache. Gegenprobe zum Commit-Wert.">?</span></div><div class="val">$(Fmt $physNetMax) GB</div><div class="hint">real belegt, ohne Cache</div></div>
    <div class="card tile"><div class="lbl">Minimal frei <span class="info" title="Wenigster freier Arbeitsspeicher waehrend der Messung. Faellt dieser Wert nahe 0, wird es eng.">?</span></div><div class="val">$(Fmt $availMin) GB</div><div class="hint">$(if($availMin -lt $lowAvailGB){"<span class='bad'>knapp</span>"}else{"<span class='good'>genug Reserve</span>"})</div></div>
    <div class="card tile"><div class="lbl">Speicherdruck <span class="info" title="Anzahl Messpunkte, in denen Windows Daten von der Platte nachladen musste UND gleichzeitig wenig RAM frei war. 0 ist gut.">?</span></div><div class="val">$pressureSamples</div><div class="hint">$(if($pressureSamples -gt 0){"<span class='bad'>Engpaesse!</span>"}else{"<span class='good'>keine Engpaesse</span>"})</div></div>
  </div>
  <p class="muted" style="margin-top:.8rem">$(HtmlEncode $pagingNote)</p>

  <h2>Pro Messtag / Lauf</h2>
  <p class="muted">So verteilt sich der Bedarf auf die einzelnen Messungen. Alle fliessen gemeinsam in die Empfehlung oben ein.</p>
  <div class="tablewrap"><table>
    <thead><tr><th>Zeitraum</th><th class="num">Messpunkte</th><th class="num">Dauer</th><th class="num">Commit Spitze</th><th class="num">Commit p99</th></tr></thead>
    <tbody>
$runRowsHtml
    </tbody>
  </table></div>
  $ignoredHtml

  $peakHtml

  <h2>Groesste Speicherverbraucher</h2>
  <p class="muted">Sortiert nach <b>privatem Speicher</b> - das ist der Speicher, den nur dieses Programm braucht (aussagekraeftiger als der Arbeitsspeicher-Wert, weil gemeinsame Windows-Bausteine dort mehrfach zaehlen).</p>
  <div class="tablewrap"><table>
    <thead><tr><th>Programm</th><th class="num">Spitze privat (GB)</th><th class="num">Mittel privat (GB)</th><th class="num">Spitze Arbeitsspeicher (GB)</th></tr></thead>
    <tbody>
$appRowsHtml
    </tbody>
  </table></div>

  <h2>Was bedeuten die Zahlen? (Erklaerung fuer alle)</h2>
  <details open>
    <summary>Begriffe einfach erklaert</summary>
    <div class="gloss"><b>Zugesicherter Speicher (Commit Charge)</b>Die Menge Arbeitsspeicher, die alle Programme zusammen bei Windows angefordert haben. <i>Warum wichtig:</i> Das ist der echte Bedarf und haengt NICHT davon ab, wie viel RAM eingebaut ist - deshalb die beste Grundlage fuer die Kaufentscheidung. <i>Guter Wert:</i> deutlich unter der geplanten RAM-Groesse.</div>
    <div class="gloss"><b>Arbeitsspeicher (Working Set)</b>Der RAM, den ein Programm gerade wirklich benutzt. <i>Achtung:</i> Gemeinsame Windows-Bausteine werden bei jedem Programm mitgezaehlt - die Summe ueber alle Programme ist deshalb zu hoch. Fuer den Vergleich einzelner Programme daher lieber der private Speicher.</div>
    <div class="gloss"><b>Privater Speicher</b>Der Speicher, den nur dieses eine Programm belegt (ohne geteilte Bausteine). <i>Warum wichtig:</i> zeigt fair, welches Programm der groesste Speicherfresser ist.</div>
    <div class="gloss"><b>Verfuegbar / frei</b>Wie viel RAM gerade noch frei ist. <i>Guter Wert:</i> immer ein paar GB uebrig. <i>Schlechter Wert:</i> nahe 0 - dann muss Windows auslagern und alles wird langsam.</div>
    <div class="gloss"><b>Datei-Cache</b>Freien RAM nutzt Windows automatisch als Zwischenspeicher, um z. B. grosse CAD-Plaene schneller zu oeffnen. Das laesst "belegt" hoch aussehen, ist aber Reserve, die sofort freigegeben wird - deshalb rechnen wir den Cache heraus.</div>
    <div class="gloss"><b>Auslagerung / Speicherdruck</b>Reicht der RAM nicht, schiebt Windows Daten auf die Festplatte (Auslagerungsdatei) - das bremst spuerbar. Wir zaehlen es nur als Problem, wenn gleichzeitig wenig RAM frei war. <i>Guter Wert:</i> 0.</div>
    <div class="gloss"><b>p99 / p95 / Median (Perzentil)</b>Sortiert man alle Messwerte, ist p99 der Wert, den 99% der Messungen nicht ueberschreiten (der Median 50%). <i>Warum wichtig:</i> p99 zeigt den praktischen Spitzenbedarf, ohne dass ein einzelner kurzer Ausreisser die Entscheidung bestimmt.</div>
    <div class="gloss"><b>Auslastung (%)</b>Benoetigter Speicher geteilt durch die RAM-Groesse. <i>Faustregel:</i> <span class="good">bis 75% komfortabel</span>, <span class="warn">bis ~100% knapp</span>, <span class="bad">darueber zu klein</span>. Etwas Reserve ist gut fuer den Datei-Cache und kuenftig groessere Programme.</div>
  </details>
  <details>
    <summary>Warum "zugesichert" nicht gleich "benoetigt" ist (wichtig fuers Downsizing)</summary>
    <div class="gloss"><b>Speicher-Inflation auf grossen Testsystemen</b>Auf einem 64-GB-Rechner "nehmen sich" viele Programme mehr Speicher, als sie eigentlich brauchen - besonders Browser (Chrome, Brave, Edge) und Electron-Apps (Teams, Slack, auch der Cursor-Editor). Sie geben Speicher erst zurueck, wenn er knapp wird (Memory Pressure / Garbage Collection). Auf einem 32-GB-System belegen dieselben Programme deshalb <b>weniger</b> - sie raeumen frueher auf.</div>
    <div class="gloss"><b>Konsequenz fuer die Empfehlung</b>Der <b>zugesicherte Speicher (Commit)</b> ist deshalb eine <i>Obergrenze</i>, nicht der echte Bedarf. Dieses Werkzeug stuft eine groessere RAM-Klasse nur dann als noetig ein, wenn <b>zusaetzlich</b> der tatsaechlich physisch belegte Speicher (Working Set, ohne Cache) hoch ist. So wird nicht wegen reservierten, aber ungenutzten Speichers zu gross gekauft. Umgekehrt gilt: Zeigt sich echter Speicherdruck (Auslagerung bei knappem RAM), ist die Klasse wirklich zu klein.</div>
  </details>

  <h2>Technische Details (fuer die IT)</h2>
  <div class="tablewrap"><table>
    <thead><tr><th>Kennzahl</th><th class="num">Wert</th><th>Erläuterung</th></tr></thead>
    <tbody>
      <tr><td>Commit Charge - Maximum</td><td class="num">$(Fmt $commitMax) GB</td><td>hoechster Einzelwert</td></tr>
      <tr><td>Commit Charge - p99 / p95 / Median</td><td class="num">$(Fmt $commitP99) / $(Fmt $commitP95) / $(Fmt $commitP50) GB</td><td>Perzentile</td></tr>
      <tr><td>Commit Charge - Mittelwert</td><td class="num">$(Fmt $commitAvg) GB</td><td>arithmetisches Mittel</td></tr>
      <tr><td>Physisch belegt (inkl. Cache) - Max / Mittel</td><td class="num">$(Fmt $physMax) / $(Fmt $physAvg) GB</td><td>Total - FreePhysicalMemory</td></tr>
      <tr><td>Physisch genutzt (ohne Cache) - Max / p99</td><td class="num">$(Fmt $physNetMax) / $(Fmt $physNetP99) GB</td><td>PhysicalInUse - CacheBytes</td></tr>
      <tr><td>Verfuegbar - Minimum</td><td class="num">$(Fmt $availMin) GB</td><td>tiefster freier RAM</td></tr>
      <tr><td>Speicherdruck-Messpunkte</td><td class="num">$pressureSamples</td><td>PageReads &gt; 50/s UND Verfuegbar &lt; $(Fmt $lowAvailGB) GB</td></tr>
      <tr><td>Auslagerung - Max (PageReads/s)</td><td class="num">$(Fmt $pageMax)</td><td>harte Seitenfehler</td></tr>
      <tr><td>Messpunkte / Dauer / Messtage</td><td class="num">$sampleCount / $spanText / $dayCount</td><td>Datenbasis</td></tr>
    </tbody>
  </table></div>
  <details>
    <summary>Methodik &amp; Schwellenwerte (nachvollziehbar)</summary>
    <div class="gloss"><b>Leitgroesse</b>Commit Charge (zugesicherter Speicher), sprachunabhaengig aus Win32_OperatingSystem abgeleitet (TotalVirtualMemorySize - FreeVirtualMemory) und via Win32_PerfFormattedData_PerfOS_Memory gegengeprueft.</div>
    <div class="gloss"><b>Ampel</b>Auslastung = Commit p95 / RAM-Groesse. Schwellen: &le;75% Komfortabel, &le;90% Ausreichend, &le;102% Grenzwertig, &gt;102% Zu klein.</div>
    <div class="gloss"><b>Zwei-Faktor-Empfehlung</b>Hochstufung 16&rarr;32 nur bei Commit p95 &gt; 12,8 GB UND Working-Set-Max &gt; $(Fmt $wsGate32) GB; 32&rarr;64 nur bei Commit p95 &gt; 25,6 GB UND Working-Set-Max &gt; $(Fmt $wsGate64) GB. Sicherheits-Override, falls Commit die Klasse komplett uebersteigt.</div>
    <div class="gloss"><b>Empfehlungs-Grundlage (dieser Lauf)</b>Commit p95 = $(Fmt $commitP95) GB, Working-Set-Max (ohne Cache) = $(Fmt $physNetMax) GB &rarr; Empfehlung $recSize GB. Commit-allein-Sicht: $commitOnlySize GB$(if($commitPhysGap){' (durch physische Gegenprobe reduziert)'}).</div>
    <div class="gloss"><b>Speicherdruck</b>Nur gewertet, wenn PageReads &gt; 50/s UND gleichzeitig Verfuegbar &lt; $(Fmt $lowAvailGB) GB (5% des RAM bzw. min. 1 GB).</div>
    <div class="gloss"><b>Datenquellen</b>Rechner $(HtmlEncode $selMachine); $($runs.Count) Datei(en)/Lauf(e); erzeugt mit Track-Memory.ps1 / Analyze-Memory.ps1.</div>
  </details>

  <footer>Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') &middot; RAM-Monitor - Detailbericht (fuer die IT)</footer>
</div>
</body>
</html>
"@
$htmlIT = $html

# ===========================================================================
# EINFACHER EIN-SEITER (fuer Nicht-Techniker / IT-Verantwortliche)
# ===========================================================================
function Simple-Label($lbl) {
    switch ($lbl) {
        'Komfortabel' { 'Reicht locker' }
        'Ausreichend' { 'Reicht gut' }
        'Grenzwertig' { 'Knapp - nur ohne Reserve' }
        default       { 'Reicht nicht' }
    }
}
$simpleCards = ""
foreach ($v in $verdicts) {
    $sl = Simple-Label $v.Label
    $isRec = ($v.Size -eq $recSize)
    $badge = if ($isRec) { "<div class='rec-badge'>&#9733; Empfehlung</div>" } else { "" }
    $ring  = if ($isRec) { "box-shadow:0 0 0 3px $($v.Color)" } else { "" }
    $simpleCards += @"
<div class="scard" style="$ring">
  <div class="dot" style="background:$($v.Color)"></div>
  <div class="ssize">$($v.Size) GB</div>
  <div class="slabel" style="color:$($v.Color)">$sl</div>
  $badge
</div>
"@
}
$top3 = if ($appTable.Count -gt 0) { (@($appTable | Select-Object -First 3 | ForEach-Object { $_.Programm }) -join ', ') } else { 'die ueblichen Programme' }

$simpleConf = ""
if ($confLevel -eq 'gering') {
    $simpleConf = "<div class='sbanner' style='background:#dc2626'>Achtung: Die Messung war bisher sehr kurz - die Empfehlung ist noch <b>nicht verlaesslich</b>. Bitte an mehreren echten Arbeitstagen weitermessen.</div>"
} elseif ($confLevel -eq 'mittel') {
    $simpleConf = "<div class='sbanner' style='background:#d97706'>Hinweis: Fuer mehr Sicherheit ueber mehrere volle Arbeitstage messen.</div>"
}

$htmlSimple = @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RAM-Empfehlung $(HtmlEncode $selMachine)</title>
<style>
  :root { --bg:#f4f6fb; --fg:#0f172a; --muted:#64748b; --card:#fff; --line:#e2e8f0; }
  @media (prefers-color-scheme: dark){ :root{ --bg:#0b1220; --fg:#e2e8f0; --muted:#94a3b8; --card:#1e293b; --line:#334155; } }
  *{box-sizing:border-box}
  body{font-family:"Segoe UI",system-ui,sans-serif;margin:0;padding:2rem 1.5rem;background:var(--bg);color:var(--fg);line-height:1.6}
  .wrap{max-width:760px;margin:0 auto}
  h1{font-size:1.5rem;margin:0 0 .3rem}
  .sub{color:var(--muted);margin-bottom:1.4rem}
  .sbanner{color:#fff;border-radius:12px;padding:.9rem 1.1rem;margin-bottom:1.2rem}
  .rec{border-radius:16px;padding:1.6rem 1.6rem;color:#fff;background:$recColor;margin-bottom:1.6rem}
  .rec .k{font-size:.8rem;text-transform:uppercase;letter-spacing:.05em;opacity:.9}
  .rec .v{font-size:3rem;font-weight:800;line-height:1;margin:.2rem 0 .5rem}
  .rec .p{font-size:1.05rem;opacity:.97}
  .cards{display:grid;grid-template-columns:repeat(3,1fr);gap:.8rem;margin:1.2rem 0}
  .scard{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:1.1rem .8rem;text-align:center;position:relative}
  .dot{width:16px;height:16px;border-radius:50%;margin:0 auto .5rem}
  .ssize{font-size:1.4rem;font-weight:800}
  .slabel{font-size:.9rem;font-weight:600;margin-top:.2rem}
  .rec-badge{margin-top:.5rem;font-size:.72rem;font-weight:700;color:var(--fg)}
  .box{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:1.1rem 1.3rem;margin:1rem 0}
  .box h2{font-size:1.05rem;margin:0 0 .4rem}
  .muted{color:var(--muted)}
  footer{margin-top:1.6rem;font-size:.8rem;color:var(--muted)}
</style>
</head>
<body>
<div class="wrap">
  <h1>Wie viel Arbeitsspeicher braucht dieser Arbeitsplatz?</h1>
  <div class="sub">Auswertung fuer Rechner <b>$(HtmlEncode $selMachine)</b> &middot; gemessen an $dayCount Tag(en)</div>

  $simpleConf

  <div class="rec">
    <div class="k">Unsere Empfehlung</div>
    <div class="v">$recSize GB</div>
    <div class="p">$(HtmlEncode $plain)</div>
  </div>

  <div class="cards">
$simpleCards
  </div>

  <div class="box">
    <h2>Was bedeutet das?</h2>
    <p class="muted">Wir haben gemessen, wie viel Arbeitsspeicher die Programme an diesem Arbeitsplatz im Alltag wirklich anfordern. Die gruen/gelb/rote Einstufung oben zeigt, welche Speichergroesse gut passt. Etwas Reserve ist eingeplant, damit auch bei vielen gleichzeitig offenen Programmen alles fluessig laeuft.</p>
  </div>

  <div class="box">
    <h2>Was wurde gemessen?</h2>
    <p class="muted">Ueber $sampleCount Messpunkte an $dayCount Tag(en) am Rechner $(HtmlEncode $selMachine). Die groessten Speicher-Verbraucher waren: <b>$(HtmlEncode $top3)</b>. Es wurden nur Speicherwerte und Programmnamen erfasst - keine Inhalte, Dateien oder Eingaben.</p>
  </div>

  <p class="muted">Mehr Details (Zahlen, Verlauf, Technik) stehen im ausfuehrlichen Bericht fuer die IT.</p>
  <footer>Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') &middot; RAM-Monitor - einfacher Bericht</footer>
</div>
</body>
</html>
"@

# ===========================================================================
# Zusammenfassung als CSV (fuer die IT / Excel)
# ===========================================================================
$allStart = ($runs | Where-Object Start | Sort-Object Start | Select-Object -First 1).Start
$allEnd   = ($runs | Where-Object End   | Sort-Object End   | Select-Object -Last 1).End
$summary = [pscustomobject]@{
    Rechner                  = $selMachine
    Von                      = if ($allStart) { $allStart.ToString('yyyy-MM-dd HH:mm') } else { '' }
    Bis                      = if ($allEnd)   { $allEnd.ToString('yyyy-MM-dd HH:mm') }   else { '' }
    Messtage                 = $dayCount
    Messpunkte               = $sampleCount
    VerbauterRAM_GB          = $totalPhys
    Commit_Max_GB            = $commitMax
    Commit_p99_GB            = $commitP99
    Commit_p95_GB            = $commitP95
    Commit_Median_GB         = $commitP50
    PhysischOhneCache_Max_GB = $physNetMax
    Verfuegbar_Min_GB        = $availMin
    Speicherdruck_Messpunkte = $pressureSamples
    Empfehlung_GB            = $recSize
    Konfidenz                = $confLevel
}

# ===========================================================================
# Dateien schreiben (je nach Zielgruppe)
# ===========================================================================
$stamp   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$written = @()

if ($Zielgruppe -eq 'IT' -or $Zielgruppe -eq 'Beide') {
    $itPath = if (-not [string]::IsNullOrWhiteSpace($OutputHtml)) { $OutputHtml } else { Join-Path $InputFolder ("IT-Detailbericht_{0}_{1}.html" -f $selMachine, $stamp) }
    $htmlIT | Out-File -FilePath $itPath -Encoding UTF8
    $written += $itPath
    $csvPath = Join-Path $InputFolder ("Zusammenfassung_{0}_{1}.csv" -f $selMachine, $stamp)
    $summary | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $written += $csvPath
}
if ($Zielgruppe -eq 'Einfach' -or $Zielgruppe -eq 'Beide') {
    $sPath = Join-Path $InputFolder ("Einfach-Bericht_{0}_{1}.html" -f $selMachine, $stamp)
    $htmlSimple | Out-File -FilePath $sPath -Encoding UTF8
    $written += $sPath
}

Write-Host " Erzeugte Exporte:" -ForegroundColor Green
foreach ($w in $written) { Write-Host ("   {0}" -f $w) }
Write-Host "===================================================================" -ForegroundColor Cyan
