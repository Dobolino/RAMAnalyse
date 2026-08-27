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
echo Neueste Berichte oeffnen ...
REM Einfacher Bericht (fuer Nicht-Techniker / IT-Verantwortlichen)
for /f "delims=" %%f in ('dir /b /o-d "%~dp0Messdaten\Einfach-Bericht_*.html" 2^>nul') do (
    start "" "%~dp0Messdaten\%%f"
    goto :openit
)
:openit
REM Ausfuehrlicher Bericht (fuer die IT)
for /f "delims=" %%f in ('dir /b /o-d "%~dp0Messdaten\IT-Detailbericht_*.html" 2^>nul') do (
    start "" "%~dp0Messdaten\%%f"
    goto :done
)
:done
echo.
echo Fertig. Berichte + Zusammenfassung (CSV) liegen im Ordner "Messdaten".
pause
