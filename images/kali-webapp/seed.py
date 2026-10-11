#!/usr/bin/env python3
"""Seed the portal database and report files. Author: Tim Rice"""
import os, sqlite3
here = os.path.dirname(__file__)
c = sqlite3.connect(os.path.join(here, "portal.db"))
c.executescript("""
DROP TABLE IF EXISTS staff; DROP TABLE IF EXISTS services;
DROP TABLE IF EXISTS secrets; DROP TABLE IF EXISTS invoices; DROP TABLE IF EXISTS users;
CREATE TABLE staff (id INTEGER PRIMARY KEY, name TEXT, title TEXT, email TEXT);
CREATE TABLE services (id INTEGER PRIMARY KEY, name TEXT, state TEXT);
CREATE TABLE secrets (id INTEGER PRIMARY KEY, key TEXT, value TEXT);
CREATE TABLE invoices (id INTEGER PRIMARY KEY, customer TEXT, amount TEXT, notes TEXT);
CREATE TABLE users (id INTEGER PRIMARY KEY, user TEXT, password TEXT, role TEXT);
""")
c.executemany("INSERT INTO staff (name,title,email) VALUES (?,?,?)", [
    ("Alice Chen","Engineer","alice.chen@corp.local"),
    ("Bob Diaz","Analyst","bob.diaz@corp.local"),
    ("Carol Frost","Manager","carol.frost@corp.local"),
])
c.executemany("INSERT INTO services (name,state) VALUES (?,?)", [
    ("web","running"),("db","running"),("cache","degraded")])
# SQL-injection prize: a table /search should never reach.
c.execute("INSERT INTO secrets (key,value) VALUES (?,?)",
          ("api_token","FLAG-sql-injection-reached-the-secrets-table"))
# IDOR: invoice 1001 belongs to another customer; no auth check lets anyone read it.
c.executemany("INSERT INTO invoices (id,customer,amount,notes) VALUES (?,?,?,?)", [
    (1,"Acme Corp","$1,200","standard"),
    (1001,"Confidential Client","$480,000","FLAG-idor-read-another-customers-invoice"),
])
# auth-bypass target: real admin creds the injection sidesteps.
c.executemany("INSERT INTO users (user,password,role) VALUES (?,?,?)", [
    ("admin","S3cr3t-do-not-guess","admin"),
    ("bob","hunter2","staff"),
])
c.commit(); c.close()
# report files for the path-traversal endpoint; a sensitive one lives outside.
os.makedirs(os.path.join(here, "reports"), exist_ok=True)
with open(os.path.join(here, "reports", "welcome.txt"), "w") as f:
    f.write("Quarterly report placeholder. Nothing sensitive here.\n")
# a sensitive file one directory ABOVE the reports folder; ../ reaches it,
# and deeper ../ reaches real files like /etc/passwd.
with open(os.path.join(here, "portal_secret.txt"), "w") as f:
    f.write("FLAG-path-traversal-escaped-the-reports-folder\n")
print("seeded")
