#!/usr/bin/env python3
"""
Internal Tools Portal - a deliberately vulnerable web app for the security labs.

Home-grown and stuffed with vulnerabilities on purpose. It is the target a
student reviews (source in ~/app) and attacks, whether with curl and an AI in
the lean SSH lab, or with Burp Suite from the Kali desktop lab. A couple of
endpoints look dangerous and are safe, so a student (or an AI) learns to prove
findings rather than assume them.

Vulnerability map (for the instructor; students discover these):
  /diag           command injection (shell)                       VULN
  /search         SQL injection (string-formatted query)          VULN
  /greet          reflected XSS                                   VULN
  /notes          stored XSS                                      VULN
  /readfile       path traversal / local file read                VULN
  /fetch          SSRF (server fetches a user-supplied URL)       VULN
  /invoice        IDOR (no auth/ownership check on an id)         VULN
  /go             open redirect                                   VULN
  /login          auth bypass (SQLi in the auth query)            VULN
  /calc           server-side eval (RCE via eval)                 VULN
  /debug          info disclosure (env + config dump)             VULN
  /api/status     parameterized query                            SAFE (decoy)
  /profile        properly escaped output                        SAFE (decoy)

Do not deploy this anywhere real. It exists to be broken.
Author: Tim Rice - tim.j.rice@hackrange.com
"""

import os
import html
import sqlite3
import subprocess
from urllib.request import urlopen
from flask import Flask, request, jsonify, Response, redirect

app = Flask(__name__)
DB = os.path.join(os.path.dirname(__file__), "portal.db")

# In-memory notes store for the stored-XSS demo.
NOTES = []


def db():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    return conn


@app.route("/")
def home():
    return Response(
        "<h2>Internal Tools Portal</h2>"
        "<p>Staff-only utilities. (You should not be reading this from outside.)</p>"
        "<ul>"
        "<li>GET  /diag?host=&lt;host&gt; &mdash; network diagnostic (ping)</li>"
        "<li>GET  /search?q=&lt;name&gt; &mdash; staff directory search</li>"
        "<li>GET  /greet?name=&lt;name&gt; &mdash; greeting</li>"
        "<li>GET/POST /notes &mdash; shared sticky notes</li>"
        "<li>GET  /readfile?name=&lt;file&gt; &mdash; read a report from the reports folder</li>"
        "<li>GET  /fetch?url=&lt;url&gt; &mdash; fetch a remote status page</li>"
        "<li>GET  /invoice?id=&lt;n&gt; &mdash; view an invoice</li>"
        "<li>GET  /go?url=&lt;url&gt; &mdash; redirect helper</li>"
        "<li>POST /login &mdash; staff login</li>"
        "<li>GET  /calc?expr=&lt;expr&gt; &mdash; quick calculator</li>"
        "<li>GET  /api/status?service=&lt;name&gt; &mdash; service health</li>"
        "<li>GET  /profile?name=&lt;name&gt; &mdash; staff profile card</li>"
        "</ul>",
        mimetype="text/html",
    )


# --- VULN: command injection -------------------------------------------------
@app.route("/diag")
def diag():
    host = request.args.get("host", "127.0.0.1")
    cmd = "ping -c 1 " + host  # user input straight into a shell command
    try:
        out = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, timeout=8)
        return Response(out.decode(errors="replace"), mimetype="text/plain")
    except subprocess.CalledProcessError as e:
        return Response(e.output.decode(errors="replace"), mimetype="text/plain")
    except Exception as e:
        return Response("error: " + str(e), mimetype="text/plain", status=500)


# --- VULN: SQL injection -----------------------------------------------------
@app.route("/search")
def search():
    q = request.args.get("q", "")
    conn = db()
    sql = "SELECT name, title, email FROM staff WHERE name LIKE '%%%s%%'" % q  # string-formatted
    try:
        rows = conn.execute(sql).fetchall()
        return jsonify([dict(r) for r in rows])
    except Exception as e:
        return Response("sql error: " + str(e), mimetype="text/plain", status=500)
    finally:
        conn.close()


# --- VULN: reflected XSS -----------------------------------------------------
@app.route("/greet")
def greet():
    name = request.args.get("name", "guest")
    # user input reflected into HTML with no escaping
    return Response("<h3>Hello, " + name + "!</h3>", mimetype="text/html")


# --- VULN: stored XSS --------------------------------------------------------
@app.route("/notes", methods=["GET", "POST"])
def notes():
    if request.method == "POST":
        NOTES.append(request.form.get("note", ""))
        return redirect("/notes")
    # every stored note rendered raw
    body = "<h3>Shared notes</h3><form method=post>" \
           "<input name=note><button>add</button></form><ul>"
    for n in NOTES:
        body += "<li>" + n + "</li>"
    return Response(body + "</ul>", mimetype="text/html")


# --- VULN: path traversal / local file read ---------------------------------
@app.route("/readfile")
def readfile():
    name = request.args.get("name", "welcome.txt")
    path = "/home/student/app/reports/" + name  # no sanitization; ../ escapes
    try:
        with open(path) as f:
            return Response(f.read(), mimetype="text/plain")
    except Exception as e:
        return Response("error: " + str(e), mimetype="text/plain", status=404)


# --- VULN: SSRF --------------------------------------------------------------
@app.route("/fetch")
def fetch():
    url = request.args.get("url", "http://127.0.0.1:5000/")
    try:
        # server fetches whatever URL the user supplies, including internal ones
        data = urlopen(url, timeout=6).read()
        return Response(data, mimetype="text/plain")
    except Exception as e:
        return Response("fetch error: " + str(e), mimetype="text/plain", status=502)


# --- VULN: IDOR --------------------------------------------------------------
@app.route("/invoice")
def invoice():
    iid = request.args.get("id", "1")
    conn = db()
    try:
        # parameterized (so no SQLi here), but NO ownership/auth check: any id works
        row = conn.execute("SELECT id, customer, amount, notes FROM invoices WHERE id = ?", (iid,)).fetchone()
        if row is None:
            return jsonify({"error": "not found"}), 404
        return jsonify(dict(row))
    finally:
        conn.close()


# --- VULN: open redirect -----------------------------------------------------
@app.route("/go")
def go():
    return redirect(request.args.get("url", "/"))  # redirects anywhere, no allowlist


# --- VULN: auth bypass via SQLi in the login query --------------------------
@app.route("/login", methods=["POST"])
def login():
    user = request.form.get("user", "")
    pw = request.form.get("password", "")
    conn = db()
    # both fields string-formatted into the query: classic auth-bypass injection
    sql = "SELECT id, user, role FROM users WHERE user = '%s' AND password = '%s'" % (user, pw)
    try:
        row = conn.execute(sql).fetchone()
        if row:
            return jsonify({"login": "ok", "user": row["user"], "role": row["role"]})
        return jsonify({"login": "failed"}), 401
    except Exception as e:
        return Response("sql error: " + str(e), mimetype="text/plain", status=500)
    finally:
        conn.close()


# --- VULN: server-side eval (RCE) -------------------------------------------
@app.route("/calc")
def calc():
    expr = request.args.get("expr", "1+1")
    try:
        return Response(str(eval(expr)), mimetype="text/plain")  # eval on user input
    except Exception as e:
        return Response("calc error: " + str(e), mimetype="text/plain", status=400)


# --- VULN: info disclosure ---------------------------------------------------
@app.route("/debug")
def debug():
    # dumps environment and config; should never be exposed
    return jsonify({
        "env": dict(os.environ),
        "db_path": DB,
        "cwd": os.getcwd(),
        "note": "DEBUG endpoint left enabled",
    })


# --- SAFE decoy: parameterized query ----------------------------------------
@app.route("/api/status")
def status():
    service = request.args.get("service", "web")
    conn = db()
    try:
        row = conn.execute("SELECT name, state FROM services WHERE name = ?", (service,)).fetchone()
        if row is None:
            return jsonify({"service": service, "state": "unknown"})
        return jsonify({"service": row["name"], "state": row["state"]})
    finally:
        conn.close()


# --- SAFE decoy: output properly escaped ------------------------------------
@app.route("/profile")
def profile():
    name = request.args.get("name", "guest")
    # looks like /greet, but escapes the input, so it is NOT XSS
    return Response("<h3>Profile: " + html.escape(name) + "</h3>", mimetype="text/html")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
