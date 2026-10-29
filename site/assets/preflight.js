/*
 * Preflight front page. Small, vanilla, no build.
 *
 * - copy buttons
 * - OS tabs (WayneUI's tab pattern: arrow keys, Home, End)
 * - the checklist that runs itself as you scroll (the magic)
 * - the guarded "inject an advisory" switch
 * - the project-settings toggles
 * - scroll reveals and the split-flap departures board
 *
 * With reduced motion the page is already the finished flight; the buttons
 * still work, instantly, and the status line says what happened.
 */
(function () {
  "use strict";

  var root = document.documentElement;
  var motion = root.classList.contains("motion");

  /* ------------------------------------------------------------- copy */
  document.querySelectorAll("[data-copy-from]").forEach(function (btn) {
    var label = btn.querySelector(".copy-btn__label");
    btn.addEventListener("click", function () {
      var src = document.querySelector(btn.getAttribute("data-copy-from"));
      if (!src) return;
      var text = src.textContent.replace(/\s+$/, "");
      var done = function () {
        btn.classList.add("is-copied");
        label.textContent = "Copied";
        setTimeout(function () { btn.classList.remove("is-copied"); label.textContent = "Copy"; }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () { label.textContent = "Select it"; });
      } else {
        label.textContent = "Select it";
      }
    });
  });

  /* ------------------------------------------------------------- tabs */
  document.querySelectorAll("[data-tabs]").forEach(function (box) {
    var tabs = Array.prototype.slice.call(box.querySelectorAll('[role="tab"]'));
    function select(tab, focus) {
      tabs.forEach(function (t) {
        var on = t === tab;
        t.setAttribute("aria-selected", on ? "true" : "false");
        t.tabIndex = on ? 0 : -1;
        document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
      });
      if (focus) tab.focus();
    }
    tabs.forEach(function (tab, i) {
      tab.addEventListener("click", function () { select(tab, false); });
      tab.addEventListener("keydown", function (e) {
        var n = null;
        if (e.key === "ArrowRight") n = tabs[(i + 1) % tabs.length];
        if (e.key === "ArrowLeft") n = tabs[(i - 1 + tabs.length) % tabs.length];
        if (e.key === "Home") n = tabs[0];
        if (e.key === "End") n = tabs[tabs.length - 1];
        if (n) { e.preventDefault(); select(n, true); }
      });
    });
    // Open on the visitor's own OS when we can tell.
    var ua = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
    if (!/win/i.test(ua) && tabs[1]) select(tabs[1], false);
  });

  /* -------------------------------------------------------- checklist */
  var pf = document.querySelector("[data-preflight]");
  if (pf) {
    var items = Array.prototype.slice.call(pf.querySelectorAll(".item"));
    var lamps = {};
    pf.querySelectorAll("[data-lamp]").forEach(function (l) { lamps[l.getAttribute("data-lamp")] = l; });
    var holds = Array.prototype.slice.call(pf.querySelectorAll("[data-hold-line]"));
    var plane = pf.querySelector("[data-plane]");
    var clearance = pf.querySelector("[data-clearance]");
    var status = pf.querySelector("[data-status]");
    var guard = pf.querySelector("[data-guard]");
    var runBtn = pf.querySelector("[data-run]");
    var auditResp = items[2].querySelector(".item__resp");

    var TOTAL = items.length;          // 8: seven jobs and the clearance
    var AUDIT = 2;                      // index of the Composer audit item
    // Where the aircraft sits after n items are done (SVG user units).
    var X = [33, 92, 186, 222, 284, 306, 326, 440];
    // Which hold-short line each count has rolled past: TEST after 2, AUDIT after 4, STYLE after 7.
    var HOLD_AT = [2, 4, 7];

    var failing = false;
    var scrollCount = motion ? 0 : TOTAL;
    var autoCount = null;               // a number while "Run the checklist" is driving
    var shown = -1;

    function setPlane(x, airborne) {
      if (!plane) return;
      plane.classList.toggle("is-airborne", !!airborne);
      plane.style.transform = airborne
        ? "translate(600px, 48px) rotate(90deg) scale(1.7)"
        : "translate(" + x + "px, 48px) rotate(90deg)";
    }

    function render(count) {
      var c = count;
      var blocked = failing && c > AUDIT;
      if (blocked) c = AUDIT + 1;       // the audit item fails; nothing after it runs
      var key = c + (blocked ? "f" : "") ;
      if (key === shown) return;
      shown = key;

      items.forEach(function (it, i) {
        var done = i < c && !(blocked && i === AUDIT);
        it.classList.toggle("is-done", done);
        it.classList.toggle("is-fail", blocked && i === AUDIT);
        it.classList.toggle("is-current", motion && i === c && c < TOTAL && !blocked);
        (it.getAttribute("data-lights") || "").split(" ").forEach(function (name, j) {
          var lamp = lamps[name];
          if (!lamp || name === "cleared") return;
          lamp.style.setProperty("--d", done ? (j * 0.16) + "s" : "0s");
          lamp.classList.toggle("is-lit", done);
          lamp.classList.toggle("is-warn", blocked && i === AUDIT);
        });
      });
      auditResp.textContent = blocked ? "Advisory found" : "No advisories";

      var cl = lamps.cleared;
      var cleared = !blocked && c >= TOTAL;
      cl.classList.toggle("is-lit", cleared);
      cl.classList.toggle("is-caution", blocked);
      clearance.textContent = blocked ? "HOLD SHORT · AUDIT FAILED" : "CLEARED FOR TAKEOFF";

      holds.forEach(function (h, i) {
        h.classList.toggle("is-passed", c >= HOLD_AT[i] && !(blocked && i === 1));
        h.classList.toggle("is-stopbar", blocked && i === 1);
      });

      if (blocked) setPlane(X[3], false);
      else if (cleared) setPlane(X[7], motion);
      else setPlane(X[Math.min(c, 7)], false);
    }

    function measure() {
      var line = window.innerHeight * (window.innerWidth < 900 ? 0.72 : 0.58);
      var n = 0;
      for (var i = 0; i < items.length; i++) {
        if (items[i].getBoundingClientRect().top + 28 < line) n = i + 1; else break;
      }
      return n;
    }

    if (motion) {
      var ticking = false;
      var onScroll = function () {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(function () {
          ticking = false;
          var n = measure();
          if (n !== scrollCount) { scrollCount = n; autoCount = null; }
          render(autoCount === null ? scrollCount : autoCount);
        });
      };
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll);
      scrollCount = measure();
    }
    render(scrollCount);
    // Let the aircraft settle where it starts before its moves are animated.
    requestAnimationFrame(function () { requestAnimationFrame(function () { pf.classList.add("is-live"); }); });

    var runTimer = null;
    function say(msg) { status.textContent = ""; setTimeout(function () { status.textContent = msg; }, 30); }
    function finalWords() {
      return failing
        ? "Holding short: the Composer audit found an advisory. Fix it and push again."
        : "Checklist complete. Cleared for takeoff, runway Citadel.";
    }

    runBtn.addEventListener("click", function () {
      clearInterval(runTimer);
      if (!motion) { render(TOTAL); say(finalWords()); return; }
      autoCount = 0;
      shown = -1;
      render(0);
      say("Running the checklist.");
      runTimer = setInterval(function () {
        autoCount += 1;
        render(autoCount);
        if (autoCount >= TOTAL || (failing && autoCount > AUDIT)) {
          clearInterval(runTimer);
          say(finalWords());
        }
      }, 520);
    });

    // closed -> open (cover up) -> on (advisory injected) -> closed
    guard.addEventListener("click", function () {
      var s = guard.getAttribute("data-state") || "closed";
      if (s === "closed") {
        guard.setAttribute("data-state", "open");
        say("Guard up. Press again to inject an advisory.");
        return;
      }
      if (s === "open") {
        guard.setAttribute("data-state", "on");
        guard.setAttribute("aria-pressed", "true");
        failing = true;
      } else {
        guard.setAttribute("data-state", "closed");
        guard.setAttribute("aria-pressed", "false");
        failing = false;
      }
      shown = -1;
      render(autoCount === null ? scrollCount : autoCount);
      say(failing
        ? "Advisory injected. The Composer audit fails, and the pipeline holds short."
        : "Advisory cleared. Guard down.");
    });
  }

  /* ---------------------------------------------- project settings */
  var arms = Array.prototype.slice.call(document.querySelectorAll("[data-arm]"));
  var armed = document.querySelector("[data-armed]");
  if (armed) {
    var armedText = armed.querySelector("[data-armed-text]");
    var update = function () {
      var n = arms.filter(function (a) { return a.checked; }).length;
      armedText.textContent = n === arms.length ? "Armed · 3 of 3 set" : n + " of " + arms.length + " set";
      armed.classList.toggle("is-armed", n === arms.length);
    };
    arms.forEach(function (a) { a.addEventListener("change", update); });
    update();
  }

  /* ---------------------------------------------------- split-flap */
  // The name stays whole for screen readers; the cells are a visual copy.
  var flaps = Array.prototype.slice.call(document.querySelectorAll("[data-flap]"));
  flaps.forEach(function (el) {
    var word = el.textContent;
    el.textContent = "";
    var sr = document.createElement("span");
    sr.className = "wsu-sr-only";
    sr.textContent = word;
    var vis = document.createElement("span");
    vis.className = "flap";
    vis.setAttribute("aria-hidden", "true");
    word.toUpperCase().split("").forEach(function (ch) {
      var c = document.createElement("span");
      c.className = "flap__c";
      c.textContent = ch;
      c.setAttribute("data-ch", ch);
      vis.appendChild(c);
    });
    el.appendChild(sr);
    el.appendChild(vis);
  });

  var ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  function flip(el) {
    // Each cell turns over a few times and lands; about eight changes a
    // second per cell, in small cells, so nothing flashes.
    el.querySelectorAll(".flap__c").forEach(function (c, i) {
      var target = c.getAttribute("data-ch");
      var turns = 3 + (i % 3);
      var k = 0;
      setTimeout(function step() {
        if (k >= turns) { c.textContent = target; return; }
        c.textContent = ALPHA.charAt(Math.floor(Math.random() * ALPHA.length));
        k += 1;
        setTimeout(step, 120);
      }, i * 50);
    });
  }

  /* -------------------------------------------------------- reveals */
  if (motion && "IntersectionObserver" in window) {
    var revealables = [];
    document.querySelectorAll(".section__head, .placard, .inop, .plan__box, .poh, .selfcheck, .card").forEach(function (el) {
      el.setAttribute("data-reveal", "");
      revealables.push(el);
    });
    document.querySelectorAll(".placards .placard").forEach(function (el, i) { el.style.setProperty("--rd", i % 3); });
    document.querySelectorAll(".plan__box").forEach(function (el, i) { el.style.setProperty("--rd", i % 2); });

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add("is-in");
        io.unobserve(e.target);
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    revealables.forEach(function (el) { io.observe(el); });

    var fo = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        fo.unobserve(e.target);
        flip(e.target);
      });
    }, { threshold: 0.6 });
    document.querySelectorAll(".flight").forEach(function (row) { fo.observe(row); });
  }
})();
