/*
 * The Local Lab control panel.  Every value from the server goes into the page
 * as text (textContent), never as HTML, so nothing it says can run as script.
 *
 * Author: Tim Rice - tim.j.rice@hackrange.com
 */
(function () {
  "use strict";
  var BUSY_POLL_MS = 2500;      // while a lab is starting, preparing or ending
  var tick = 0;
  var state = null;
  var cards = {};

  var $ = function (id) { return document.getElementById(id); };

  function api(path, body) {
    var opts = { credentials: "same-origin", headers: {} };
    if (body !== undefined) {
      opts.method = "POST";
      opts.headers["Content-Type"] = "application/json";
      opts.headers["X-HR-Request"] = "1";       // the server refuses changes without it
      opts.body = JSON.stringify(body);
    }
    return fetch(path, opts).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) { j._status = r.status; return j; });
    });
  }

  function gb(bytes) { return (bytes / 1073741824).toFixed(1) + " GB"; }
  function mb(bytes) { return bytes >= 1073741824 ? gb(bytes) : Math.round(bytes / 1048576) + " MB"; }
  function rate(bytes) {
    if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB/s";
    if (bytes >= 1024) return Math.round(bytes / 1024) + " kB/s";
    return bytes + " B/s";
  }
  function level(pct) { return pct >= 85 ? "high" : pct >= 60 ? "warn" : ""; }

  function setMeter(key, pct, value, note) {
    var bar = $(key + "-bar");
    bar.style.width = Math.min(100, Math.max(0, pct)) + "%";
    bar.className = level(pct);
    $(key + "-value").textContent = value;
    $(key + "-note").textContent = note;
  }

  var STATE_TEXT = {
    "running": "Running", "starting": "Starting", "preparing": "Preparing",
    "stopping": "Ending", "stopped": "Not running",
    "not-built": "Image not built", "unknown": "Checking"
  };

  // What ending a lab costs, in the words the launcher itself uses.  A student
  // is about to lose work if they have not copied it out, so the confirmation
  // has to say that rather than ask "are you sure?".
  function confirmStop(lab) {
    return confirm("End the " + lab.key + " lab?\n\n" +
      "This deletes the lab machine and everything in it.  Anything you made " +
      "inside it and have not copied out is gone, and it cannot be undone.");
  }

  function confirmStart(lab, running) {
    if (!running || running === lab.key) {
      return confirm("Start the " + lab.key + " lab?\n\n" +
        "It takes a minute or two.  The card says Preparing until the lab will " +
        "actually let you in, and then offers a button to open it.");
    }
    return confirm("Start the " + lab.key + " lab, and end the " + running + " lab?\n\n" +
      "One lab runs at a time, so the " + running + " lab is deleted, with everything " +
      "in it.  Copy out anything you want to keep first.");
  }

  function copyButton(text) {
    var b = document.createElement("button");
    b.className = "small";
    b.textContent = "Copy";
    b.addEventListener("click", function () {
      navigator.clipboard.writeText(text).then(function () {
        b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1200);
      });
    });
    return b;
  }

  function kv(label, value, secret, note) {
    var row = document.createElement("div");
    row.className = "kv";
    var l = document.createElement("span"); l.textContent = label;
    var c = document.createElement("code");
    row.appendChild(l); row.appendChild(c);
    if (secret) {
      c.textContent = "••••••••"; c.className = "secret masked";
      var show = document.createElement("button"); show.className = "small"; show.textContent = "Show";
      show.addEventListener("click", function () {
        var hidden = c.classList.toggle("masked");
        c.textContent = hidden ? "••••••••" : value;
        show.textContent = hidden ? "Show" : "Hide";
      });
      row.appendChild(show);
    } else {
      c.textContent = value;
    }
    row.appendChild(copyButton(value));
    if (note) {
      var n = document.createElement("span"); n.className = "cred-note"; n.textContent = note;
      row.appendChild(n);
    }
    return row;
  }

  function buildCard(lab) {
    var node = document.getElementById("lab-template").content.firstElementChild.cloneNode(true);
    node.querySelector(".comp-name").textContent = lab.title;
    node.querySelector(".comp-week").textContent = "Week " + lab.weeks;
    node.querySelector(".comp-kind").textContent = lab.proto === "ssh" ? "Terminal" : "Desktop";
    node.querySelector(".comp-desc").textContent = lab.what;
    node.querySelector(".comp-start").addEventListener("click", function () {
      if (confirmStart(lab, state && state.running)) act(lab, "start");
    });
    node.querySelector(".comp-stop").addEventListener("click", function () {
      if (confirmStop(lab)) act(lab, "stop");
    });
    node.querySelector(".comp-check").addEventListener("click", function () {
      api("api/labs/" + lab.key + "/check", { confirm: lab.key }).then(function (r) {
        if (r._status === 401) return showLogin();
        if (!r.ok) alert(r.message || "That did not work.");
        refresh();
      });
    });
    $("labs").appendChild(node);
    cards[lab.key] = node;
    return node;
  }

  function fillLinks(node, lab, info) {
    // Rebuilt only when the addresses or logins change, so a password the
    // student chose to show stays shown, and a link is not replaced under the
    // pointer on every poll.
    var sig = JSON.stringify([lab.web, lab.state, lab.logins, lab.notice, info.desktop_url]);
    if (node.dataset.sig === sig) return;
    node.dataset.sig = sig;
    var links = node.querySelector(".comp-links");
    var creds = node.querySelector(".comp-creds");
    links.textContent = ""; creds.textContent = "";
    var group = "";
    (lab.logins || []).forEach(function (row) {
      if (row.group !== group) {
        group = row.group;
        var h = document.createElement("p"); h.className = "cred-group"; h.textContent = group;
        creds.appendChild(h);
      }
      creds.appendChild(kv(row.label, row.value, row.secret, row.note));
    });
    lab.web.forEach(function (w) {
      var row = document.createElement("div");
      var l = document.createElement("span"); l.className = "usage"; l.textContent = w.label + ": ";
      var a = document.createElement("a");
      a.href = w.url; a.target = "_blank"; a.rel = "noopener noreferrer"; a.textContent = w.url;
      row.appendChild(l); row.appendChild(a);
      links.appendChild(row);
    });
  }

  function render() {
    var s = state, h = s.host || {};
    if (h.memory) {
      setMeter("cpu", h.cpu || 0, (h.cpu || 0).toFixed(0) + "%", h.cores + " cores, load " + (h.load || 0).toFixed(2));
      var mp = 100 * h.memory.used / h.memory.total;
      setMeter("mem", mp, mp.toFixed(0) + "%", gb(h.memory.used) + " of " + gb(h.memory.total) + " in use");
      var dp = 100 * h.disk.used / h.disk.total;
      setMeter("disk", dp, dp.toFixed(0) + "%", gb(h.disk.total - h.disk.used) + " free of " + gb(h.disk.total));
      var net = h.net || {};
      if (net.measured) {
        var busiest = Math.max(net.rx || 0, net.tx || 0);
        // No percentage to show: a network has no total to be a share of.  The
        // bar is a rough sense of busy against 10 MB/s, and the numbers below
        // it are the real answer.
        setMeter("net", 100 * busiest / 10485760, rate(busiest),
                 "down " + rate(net.rx || 0) + ", up " + rate(net.tx || 0));
      } else {
        setMeter("net", 0, "-", "measuring...");
      }
    }

    var info = s.info || {};
    var pass = $("acc-pass");
    pass.dataset.value = info.password || "";
    if (!pass.dataset.shown) { pass.textContent = "••••••••"; pass.classList.add("masked"); }
    else { pass.textContent = info.password || ""; }
    var web = $("acc-web"); web.href = info.web_host || "#"; web.textContent = info.web_host || "";
    $("acc-ssh").textContent = info.ssh_host || "";
    $("acc-rdp").textContent = info.rdp_host || "";
    $("acc-where").textContent = info.machine_ip
      ? "These addresses work from any computer on your own network.  The lab never answers the internet."
      : "This machine has no private network address, so use the 127.0.0.1 addresses on the machine itself.";

    var running = 0;
    (s.labs || []).forEach(function (lab) {
      var node = cards[lab.key] || buildCard(lab);
      var pill = node.querySelector(".comp-state");
      pill.textContent = STATE_TEXT[lab.state] || lab.state;
      pill.className = "pill comp-state pill-" + lab.state;
      node.classList.toggle("is-running", lab.state === "running");
      node.classList.toggle("is-preparing", lab.state === "preparing");

      var u = lab.usage || {};
      node.querySelector(".comp-usage").textContent = (lab.state === "running" || lab.state === "starting"
                                                       || lab.state === "preparing")
        ? ("CPU " + (u.cpu || 0).toFixed(1) + "%   Memory " + mb(u.mem || 0) +
           (u.measured ? "   Network " + rate(u.rx || 0) + " down, " + rate(u.tx || 0) + " up" : ""))
        : "";

      // "preparing" means the lab exists but cannot be opened yet: its own
      // door is not answering, or the web desktop has not been pointed at it.
      // It is deliberately not treated as running, because offering an Open
      // button here is exactly what sent a student to a page that refused
      // them for the next two minutes with no explanation.
      var notice = node.querySelector(".comp-notice");
      notice.textContent = lab.notice || "";
      notice.hidden = !lab.notice;

      var busy = lab.state === "starting" || lab.state === "stopping" || lab.state === "preparing";
      var elsewhere = s.busy && s.busy !== lab.key;
      var start = node.querySelector(".comp-start");
      var open = node.querySelector(".comp-open");
      var check = node.querySelector(".comp-check");
      var stop = node.querySelector(".comp-stop");

      start.hidden = lab.state === "running" || busy;
      start.disabled = lab.state === "not-built" || elsewhere;
      start.textContent = lab.state === "not-built" ? "Not built" : "Start this lab";
      if (busy) {
        // One honest button while something is happening, rather than a Start
        // that does nothing and a Stop that would fight it.
        start.hidden = false; start.disabled = true;
        start.textContent = lab.state === "stopping" ? "Ending..."
          : lab.state === "preparing" ? "Preparing..." : "Starting...";
      }
      open.hidden = lab.state !== "running";
      // The panel's own door, which signs the student into the web desktop
      // and then redirects, so one password is asked for once.
      open.href = "open";
      open.textContent = "Open the lab";
      // Except for an emulated lab that has a web app of its own.  Splunk on
      // an ARM machine is the one: everything the lesson does is in Splunk's
      // own pages, and reaching them through the web desktop means every
      // frame of an emulated browser is drawn under translation and then sent
      // over a remote desktop.  Opened straight from the student's browser,
      // only Splunk is emulated and the drawing is native.  So the button
      // goes where the work is, instead of offering a route that is worse.
      // The lab's desktop is not offered here at all, and is not mentioned.
      // It does connect, and drawing it under emulation is slow enough to be
      // practically unusable, so naming it as an option only invites a
      // student to spend a lesson finding that out.
      if (lab.emulated && lab.web && lab.web.length) {
        open.href = lab.web[0].url;
        open.textContent = "Open " + lab.web[0].label + " in your browser";
      }
      check.hidden = lab.state !== "running";
      check.disabled = (s.check && s.check.state === "running");
      check.textContent = (s.check && s.check.state === "running" && s.check.key === lab.key)
        ? "Checking..." : "Check my work";
      // Ending stays available while a lab prepares, so a student who started
      // the wrong one is not made to wait for it before they can change it.
      stop.hidden = !(lab.state === "running" || lab.state === "preparing");

      var err = node.querySelector(".comp-error");
      err.hidden = !lab.error;
      err.textContent = lab.error ? "Last try: " + lab.error : "";
      fillLinks(node, lab, info);
      if (lab.state === "running") running++;
    });

    var sum = $("summary");
    var preparing = (s.labs || []).filter(function (l) { return l.state === "preparing"; })[0];
    if (s.busy) { sum.textContent = "Working on the " + s.busy + " lab"; sum.className = "pill pill-starting"; }
    else if (preparing) {
      sum.textContent = "Preparing the " + preparing.key + " lab";
      sum.className = "pill pill-preparing";
    }
    else if (running) { sum.textContent = "The " + s.running + " lab is running"; sum.className = "pill pill-running"; }
    else { sum.textContent = "No lab running"; sum.className = "pill pill-muted"; }

    renderCheck(s.check || {});
    $("updated").textContent = "Updated " + new Date().toLocaleTimeString();
  }

  function renderCheck(c) {
    var card = $("check-card");
    if (!c.key) { card.hidden = true; return; }
    card.hidden = false;
    $("check-title").textContent = "Your work in the " + c.key + " lab";
    $("check-when").textContent = c.state === "running"
      ? "Checking now..."
      : "Checked " + new Date((c.at || 0) * 1000).toLocaleTimeString();
    $("check-output").textContent = c.state === "running"
      ? "Marking your work inside the lab.  This takes a few seconds."
      : (c.output || "Nothing came back.");
  }

  function act(lab, action) {
    api("api/labs/" + lab.key + "/" + action, { confirm: lab.key }).then(function (r) {
      if (r._status === 401) return showLogin();
      if (!r.ok) alert(r.message || "That did not work.");
      refresh();
    });
  }

  function refresh() {
    return api("api/state").then(function (s) {
      if (s._status === 401) return showLogin();
      state = s;
      $("login").hidden = true;
      $("app").hidden = false;
      $("signout").hidden = s.door === "lab";
      render();
    }).catch(function () {
      $("summary").textContent = "Cannot reach the lab"; $("summary").className = "pill pill-stopped";
    });
  }

  function showLogin() {
    $("app").hidden = true;
    $("login").hidden = false; $("signout").hidden = true;
    $("summary").textContent = "Signed out"; $("summary").className = "pill pill-muted";
  }

  function wire() {
    document.querySelectorAll("[data-copy]").forEach(function (b) {
      b.addEventListener("click", function () {
        var el = $(b.dataset.copy);
        navigator.clipboard.writeText(el.dataset.value || el.textContent).then(function () {
          b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1200);
        });
      });
    });
    document.querySelectorAll("[data-reveal]").forEach(function (b) {
      b.addEventListener("click", function () {
        var el = $(b.dataset.reveal);
        if (el.dataset.shown) { delete el.dataset.shown; el.textContent = "••••••••"; el.classList.add("masked"); b.textContent = "Show"; }
        else { el.dataset.shown = "1"; el.textContent = el.dataset.value || ""; el.classList.remove("masked"); b.textContent = "Hide"; }
      });
    });
    $("login-form").addEventListener("submit", function (e) {
      e.preventDefault();
      var f = e.target;
      api("api/login", { username: f.username.value, password: f.password.value }).then(function (r) {
        if (r.ok) { f.password.value = ""; $("login-error").hidden = true; refresh(); }
        else { $("login-error").textContent = r.error || "That did not work."; $("login-error").hidden = false; }
      });
    });
    $("signout").addEventListener("click", function () { api("api/logout", {}).then(showLogin); });
  }

  wire();
  refresh();
  // While something is happening the page polls faster, because a student is
  // watching it rather than glancing at it.
  setInterval(function () {
    if ($("app").hidden) return;
    var moving = state && (state.busy || (state.labs || []).some(function (l) {
      return l.state === "preparing" || l.state === "starting" || l.state === "stopping";
    }));
    if (moving || tick % 2 === 0) refresh();
    tick++;
  }, BUSY_POLL_MS);
})();
