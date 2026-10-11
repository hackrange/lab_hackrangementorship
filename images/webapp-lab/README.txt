Internal Tools Portal - security review lab
===========================================

A small web application is running on this machine at http://127.0.0.1:5000.
Its full source code is in ~/app (app.py). Your job is to review it, find the
vulnerabilities, and PROVE each one against the running app.

Try the app:
  curl "http://127.0.0.1:5000/"
  curl "http://127.0.0.1:5000/diag?host=127.0.0.1"
  curl "http://127.0.0.1:5000/search?q=Alice"
  curl "http://127.0.0.1:5000/api/status?service=web"

Read the source:
  cat ~/app/app.py

The point of the exercise is in the lesson. Use AI to help you review the
source, then VERIFY every claim it makes against the running app. Not every
endpoint that looks dangerous is.
