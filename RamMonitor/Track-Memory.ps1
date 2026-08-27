<#
.SYNOPSIS
    Protokolliert den Arbeitsspeicher-Verbrauch von Windows 11 - systemweit
    und pro Programm - in CSV-Dateien, um den echten RAM-Bedarf zu ermitteln.

.BESCHREIBUNG
    Das Skript nimmt in einem festen Intervall (Standard: alle 60 Sekunden)
    Messwerte auf und haengt sie an CSV-Dateien an. Es laeuft so lange, bis
    man es mit STRG+C beendet oder die optionale Laufzeit erreicht ist.

    Die WICHTIGSTE Kennzahl fuer die Frage "reichen 32 GB / 16 GB?" ist die
    "zugesicherte" Speichermenge (Commit Charge / CommittedBytes). Das ist die
    Menge Speicher, die alle Programme zusammen tatsaechlich ANGEFORDERT haben -
    unabhaengig davon, wie viel RAM verbaut ist. Windows nutzt freien RAM als
    Cache, deshalb ist die reine "belegt"-Anzeige irrefuehrend. Commit Charge
    ist die belastbare Groesse fuer die Dimensionierung.

.PARAMETER IntervalSeconds
    Messintervall in Sekunden. Standard: 60.

.PARAMETER OutputFolder
    Zielordner fuer die CSV-Dateien. Standard: Unterordner "Messdaten" neben
    dem Skript.

.PARAMETER DurationMinutes
    Optionale Laufzeit in Minuten. 0 = unbegrenzt (bis STRG+C). Standard: 0.

.PARAMETER TopProcesses
    Wie viele der groessten Programme pro Messung einzeln erfasst werden.
    Der Rest wird als "(sonstige)" zusammengefasst. Standard: 25.

.BEISPIEL
    .\Track-Memory.ps1
    Startet die Messung mit 60-Sekunden-Intervall bis STRG+C.

.BEISPIEL
    .\Track-Memory.ps1 -IntervalSeconds 30 -DurationMinutes 480
    Misst alle 30 Sekunden ueber 8 Stunden.
#>

[CmdletBinding()]
param(
    [int]$IntervalSeconds = 60,
    [string]$OutputFolder,
    [int]$DurationMinutes = 0,
    [int]$TopProcesses = 25
)

# ---------------------------------------------------------------------------
# Vorbereitung
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

# Standard-Ausgabeordner neben dem Skript
if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $OutputFolder = Join-Path $scriptDir 'Messdaten'
}
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

# Rechnername + Startzeit in die Dateinamen, damit sich Laeufe (und mehrere
# Test-PCs) nicht gegenseitig ueberschreiben.
$stamp       = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$machine     = $env:COMPUTERNAME
$systemCsv   = Join-Path $OutputFolder ("system_{0}_{1}.csv"    -f $machine, $stamp)
$processCsv  = Join-Path $OutputFolder ("prozesse_{0}_{1}.csv"  -f $machine, $stamp)

# Physischer Gesamtspeicher (einmalig, aendert sich nicht).
$os            = Get-CimInstance Win32_OperatingSystem
$totalPhysGB   = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)   # KB -> GB

$startTime = Get-Date
$endTime   = if ($DurationMinutes -gt 0) { $startTime.AddMinutes($DurationMinutes) } else { [datetime]::MaxValue }

Write-Host ""
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host " Arbeitsspeicher-Messung gestartet" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host (" Rechner        : {0}" -f $machine)
Write-Host (" Physischer RAM : {0} GB" -f $totalPhysGB)
Write-Host (" Intervall      : {0} s" -f $IntervalSeconds)
Write-Host (" Laufzeit       : {0}" -f $(if ($DurationMinutes -gt 0) { "$DurationMinutes min" } else { "unbegrenzt (STRG+C zum Beenden)" }))
Write-Host (" System-CSV     : {0}" -f $systemCsv)
Write-Host (" Prozess-CSV    : {0}" -f $processCsv)
Write-Host "-------------------------------------------------------------------"
Write-Host " Laeuft ... Fenster offen lassen. Beenden mit STRG+C." -ForegroundColor Yellow
Write-Host ""

# ---------------------------------------------------------------------------
# Hilfsfunktion: eine Systemmessung liefern
# ---------------------------------------------------------------------------
function Get-SystemSample {
    $ts = Get-Date

    # Betriebssystem-Werte (Eigenschaftsnamen sind sprachunabhaengig, in KB).
    $osNow      = Get-CimInstance Win32_OperatingSystem
    $freePhysGB = [math]::Round($osNow.FreePhysicalMemory / 1MB, 2)
    $inUsePhysGB= [math]::Round(($osNow.TotalVisibleMemorySize - $osNow.FreePhysicalMemory) / 1MB, 2)

    # Commit Charge / Grenze aus dem Betriebssystem ableiten (immer verfuegbar):
    #   TotalVirtualMemorySize = Commit-Grenze (physisch + Auslagerungsdatei)
    #   FreeVirtualMemory      = noch freie Zusicherung
    $commitLimitGB = [math]::Round($osNow.TotalVirtualMemorySize / 1MB, 2)
    $committedGB   = [math]::Round(($osNow.TotalVirtualMemorySize - $osNow.FreeVirtualMemory) / 1MB, 2)

    # Feinere Speicher-Kennzahlen ueber den Performance-Counter (formatierte
    # Klasse, ebenfalls sprachunabhaengige Property-Namen). Falls nicht
    # verfuegbar, bleiben die OS-Werte oben massgeblich.
    $availGB = $freePhysGB
    $cacheGB = 0
    $commitPct = if ($commitLimitGB -gt 0) { [math]::Round($committedGB / $commitLimitGB * 100, 1) } else { 0 }
    $pageReadsPerSec = 0
    $pagesPerSec = 0
    try {
        $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        if ($mem) {
            if ($mem.AvailableBytes)     { $availGB   = [math]::Round($mem.AvailableBytes / 1GB, 2) }
            if ($mem.CommittedBytes)     { $committedGB = [math]::Round($mem.CommittedBytes / 1GB, 2) }
            if ($mem.CommitLimit)        { $commitLimitGB = [math]::Round($mem.CommitLimit / 1GB, 2) }
            if ($null -ne $mem.PercentCommittedBytesInUse) { $commitPct = [double]$mem.PercentCommittedBytesInUse }
            if ($mem.CacheBytes)         { $cacheGB   = [math]::Round($mem.CacheBytes / 1GB, 2) }
            # Harte Seitenfehler = echtes Nachladen von der Platte. Hohe Werte
            # bei gleichzeitig wenig verfuegbarem RAM = Speichermangel.
            if ($null -ne $mem.PageReadsPerSec) { $pageReadsPerSec = [double]$mem.PageReadsPerSec }
            if ($null -ne $mem.PagesPerSec)     { $pagesPerSec     = [double]$mem.PagesPerSec }
        }
    } catch {
        # Counter nicht verfuegbar - OS-Werte reichen fuer die Auswertung.
    }

    [pscustomobject]@{
        Timestamp        = $ts.ToString('yyyy-MM-dd HH:mm:ss')
        TotalPhysicalGB  = $totalPhysGB
        PhysicalInUseGB  = $inUsePhysGB
        AvailableGB      = $availGB
        CommittedGB      = $committedGB
        CommitLimitGB    = $commitLimitGB
        CommitPercent    = $commitPct
        CacheGB          = $cacheGB
        PageReadsPerSec  = [math]::Round($pageReadsPerSec, 1)
        PagesPerSec      = [math]::Round($pagesPerSec, 1)
    }
}

# ---------------------------------------------------------------------------
# Hilfsfunktion: Prozessmessung (pro Programmname zusammengefasst)
# ---------------------------------------------------------------------------
function Get-ProcessSample {
    param([string]$Timestamp)

    $groups = Get-Process | Group-Object -Property ProcessName | ForEach-Object {
        [pscustomobject]@{
            Name          = $_.Name
            InstanceCount = $_.Count
            WorkingSetGB  = [math]::Round((($_.Group | Measure-Object WorkingSet64        -Sum).Sum) / 1GB, 3)
            PrivateGB     = [math]::Round((($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum) / 1GB, 3)
        }
    }

    # Groesste Verbraucher einzeln, Rest zusammenfassen -> kompakte CSV.
    $sorted = $groups | Sort-Object WorkingSetGB -Descending
    $top    = $sorted | Select-Object -First $TopProcesses
    $rest   = $sorted | Select-Object -Skip  $TopProcesses

    $rows = foreach ($g in $top) {
        [pscustomobject]@{
            Timestamp     = $Timestamp
            ProcessName   = $g.Name
            InstanceCount = $g.InstanceCount
            WorkingSetGB  = $g.WorkingSetGB
            PrivateGB     = $g.PrivateGB
        }
    }

    if ($rest) {
        $rows += [pscustomobject]@{
            Timestamp     = $Timestamp
            ProcessName   = '(sonstige)'
            InstanceCount = ($rest | Measure-Object InstanceCount -Sum).Sum
            WorkingSetGB  = [math]::Round(($rest | Measure-Object WorkingSetGB -Sum).Sum, 3)
            PrivateGB     = [math]::Round(($rest | Measure-Object PrivateGB    -Sum).Sum, 3)
        }
    }
    return $rows
}

# ---------------------------------------------------------------------------
# Messschleife
# ---------------------------------------------------------------------------
$sampleNo = 0
try {
    while ((Get-Date) -lt $endTime) {
        $sampleNo++
        try {
            $sys  = Get-SystemSample
            $proc = Get-ProcessSample -Timestamp $sys.Timestamp

            # Anhaengen; Export-Csv -Append schreibt die Kopfzeile nur beim
            # ersten Mal. Jede Messung wird sofort geschrieben (kein Datenverlust
            # bei Absturz / Ausschalten).
            $sys  | Export-Csv -Path $systemCsv  -NoTypeInformation -Append -Encoding UTF8
            $proc | Export-Csv -Path $processCsv -NoTypeInformation -Append -Encoding UTF8

            # Live-Statuszeile
            $line = ("[{0}] #{1,-5} belegt {2,6} GB | verfuegbar {3,6} GB | zugesichert {4,6}/{5} GB ({6}%)" -f `
                (Get-Date -Format 'HH:mm:ss'), $sampleNo, $sys.PhysicalInUseGB, $sys.AvailableGB, `
                $sys.CommittedGB, $sys.CommitLimitGB, $sys.CommitPercent)
            if ($sys.PageReadsPerSec -gt 50) {
                Write-Host ($line + ("  ! Auslagerung: {0} Seiten/s" -f $sys.PageReadsPerSec)) -ForegroundColor Red
            } else {
                Write-Host $line
            }
        }
        catch {
            Write-Warning ("Messung #{0} fehlgeschlagen: {1}" -f $sampleNo, $_.Exception.Message)
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
}
finally {
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host (" Messung beendet. {0} Messpunkte aufgezeichnet." -f $sampleNo) -ForegroundColor Cyan
    Write-Host (" System-CSV  : {0}" -f $systemCsv)
    Write-Host (" Prozess-CSV : {0}" -f $processCsv)
    Write-Host ""
    Write-Host " Auswertung starten mit:" -ForegroundColor Yellow
    Write-Host ("   .\Analyze-Memory.ps1 -SystemCsv `"{0}`" -ProcessCsv `"{1}`"" -f $systemCsv, $processCsv)
    Write-Host "==================================================================="  -ForegroundColor Cyan
}
