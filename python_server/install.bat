cd /d %~dp0
py -m venv venv
call ".\venv\Scripts\activate.bat"
pip install -r requirements.txt