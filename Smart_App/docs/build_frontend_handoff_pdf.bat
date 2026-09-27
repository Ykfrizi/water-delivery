@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "HTML=%SCRIPT_DIR%Frontend_Developer_Handoff.html"
set "PDF=%SCRIPT_DIR%Frontend_Developer_Handoff.pdf"
if not exist "%HTML%" (
  echo Missing: %HTML%
  exit /b 1
)
set "FILE_URL=file:///%HTML:\=/%"
set "EDGE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if exist "%EDGE%" (
  "%EDGE%" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="%PDF%" "%FILE_URL%"
  if exist "%PDF%" (
    echo Created: %PDF%
    exit /b 0
  )
)
set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if exist "%CHROME%" (
  "%CHROME%" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="%PDF%" "%FILE_URL%"
  if exist "%PDF%" (
    echo Created: %PDF%
    exit /b 0
  )
)
echo Could not find Edge or Chrome to print PDF.
echo Alternative: run ^`composer update^` then ^`php scripts/generate_frontend_handoff_pdf.php^`
exit /b 1
