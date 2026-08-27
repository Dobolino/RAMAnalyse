@echo off
REM ---------------------------------------------------------------------------
REM  Doppelklick-Starter fuer die Arbeitsspeicher-Messung.
REM  Startet Track-Memory.ps1 und umgeht die PowerShell-Ausfuehrungssperre
REM  nur fuer diesen einen Aufruf (keine dauerhafte Systemaenderung).
REM ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"
echo Starte Arbeitsspeicher-Messung ...
echo Fenster offen lassen. Beenden mit STRG+C.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Track-Memory.ps1" %*
echo.
echo Messung beendet. Fenster kann geschlossen werden.
pause
