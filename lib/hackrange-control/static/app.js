/*
 * The Local Lab control panel.  Every value from the server goes into the page
 * as text (textContent), never as HTML, so nothing it says can run as script.
 *
 * Author: Tim Rice - tim.j.rice@hackrange.com
 */
(function () {
  "use strict";
  var POLL_MS = 5000;
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
    "running": "Running", "starting": "Starting", "stopping": "Ending", "stopped": "Not running",
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
        "It gets a new password, so the one you are signed in with now changes.  " +
        "The panel shows the new one when it is ready.");
    }
    return confirm("Start the " + lab.key + " lab, and end the " + running + " lab?\n\n" +
      "One lab runs at a time, so the " + running + " lab is deleted, with everything " +
      "in it.  Copy out anything you want to keep first.\n\n" +
      "The lab password changes too; the panel shows the new one when it is ready.");
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
    // Rebuilt only when the addresses change, so a link is not replaced under
    // the pointer on every poll.
    var sig = JSON.stringify([lab.web, lab.state, info.desktop_url]);
    if (node.dataset.sig === sig) return;
    node.dataset.sig = sig;
    var links = node.querySelector(".comp-links");
    links.textContent = "";
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

      var u = lab.usage || {};
      node.querySelector(".comp-usage").textContent = (lab.state === "running" || lab.state === "starting")
        ? ("CPU " + (u.cpu || 0).toFixed(1) + "%   Memory " + mb(u.mem || 0) +
           (u.measured ? "   Network " + rate(u.rx || 0) + " down, " + rate(u.tx || 0) + " up" : ""))
        : "";

      var busy = lab.state === "starting" || lab.state === "stopping";
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
        start.textContent = lab.state === "starting" ? "Starting..." : "Ending...";
      }
      open.hidden = lab.state !== "running";
      open.href = info.desktop_url || "#";
      check.hidden = lab.state !== "running";
      check.disabled = (s.check && s.check.state === "running");
      check.textContent = (s.check && s.check.state === "running" && s.check.key === lab.key)
        ? "Checking..." : "Check my work";
      stop.hidden = lab.state !== "running";

      var err = node.querySelector(".comp-error");
      err.hidden = !lab.error;
      err.textContent = lab.error ? "Last try: " + lab.error : "";
      fillLinks(node, lab, info);
      if (lab.state === "running") running++;
    });

    var sum = $("summary");
    if (s.busy) { sum.textContent = "Working on the " + s.busy + " lab"; sum.className = "pill pill-starting"; }
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
  setInterval(function () { if (!$("app").hidden) refresh(); }, POLL_MS);
})();
