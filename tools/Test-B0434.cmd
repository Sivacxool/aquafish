@echo off
chcp 65001 >nul
set "PYTHON_EXE=%~dp0..\.venv-pairing\Scripts\python.exe"
if not exist "%PYTHON_EXE%" (
    echo Run Install-ETT-B0434-Test.cmd first.
    pause
    exit /b 1
)
"%PYTHON_EXE%" -X utf8 "%~dp0test_b0434_capture.py" %*
set "TEST_EXIT=%errorlevel%"
pause
exit /b %TEST_EXIT%
