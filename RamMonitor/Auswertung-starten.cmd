@echo off
REM ---------------------------------------------------------------------------
REM  Doppelklick-Starter fuer die Auswertung.
REM  Nimmt automatisch die neueste Messung im Ordner "Messdaten" und erzeugt
REM  einen HTML-Bericht, der danach geoeffnet wird.
REM ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Analyze-Memory.ps1" %*
echo.
echo Neuesten HTML-Bericht oeffnen ...
for /f "delims=" %%f in ('dir /b /o-d "%~dp0Messdaten\Bericht_*.html" 2^>nul') do (
    start "" "%~dp0Messdaten\%%f"
    goto :done
)
:done
pause
