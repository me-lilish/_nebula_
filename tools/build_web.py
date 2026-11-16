"""
Builds the browser version of the game (phones + desktops) with love.js.

    python tools/build_web.py <output folder> [path to love.js index.js]

1. Packs main.lua, conf.lua, src/ and assets/ into game.love
2. Runs love.js in compatibility mode (no threads, so it works on plain
   static hosting such as GitHub Pages):  npx love.js -c ...
3. Restyles the generated page: full screen, 16:9 letterbox, phone meta tags,
   a "tap to play" start screen (browsers only allow sound after a tap)

Needs Node.js. The love.js packager is installed with:  npm install love.js@11.4.1
"""
import os
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
INCLUDE = ["main.lua", "conf.lua", "src", "assets"]


def pack(love_path):
    with zipfile.ZipFile(love_path, "w", zipfile.ZIP_DEFLATED) as z:
        for item in INCLUDE:
            full = os.path.join(ROOT, item)
            if os.path.isfile(full):
                z.write(full, item)
            elif os.path.isdir(full):
                for dirpath, _, files in os.walk(full):
                    for f in files:
                        if f.endswith((".pyc",)):
                            continue
                        p = os.path.join(dirpath, f)
                        z.write(p, os.path.relpath(p, ROOT).replace("\\", "/"))
    return os.path.getsize(love_path)


STYLE = """
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="theme-color" content="#0B0920">
    <link rel="icon" href="icon.png">
    <style>
      html, body { margin: 0; height: 100%; background: #0B0920; overflow: hidden; touch-action: none;
        overscroll-behavior: none; -webkit-text-size-adjust: 100%;
        -webkit-user-select: none; user-select: none; -webkit-tap-highlight-color: transparent; }
      /* iPhone: no rubber-band scrolling that would move the game */
      body { position: fixed; inset: 0; }
      /* reads the screen's safe areas (notch, home bar) as pixels */
      #safe { position: fixed; visibility: hidden; pointer-events: none; left: 0; top: 0;
        padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left); }
      #iostip { display: none; color: #FFD84D; font-weight: 400; font-size: 15px; padding: 0 24px; max-width: 520px; }
      center > div > h1, footer { display: none; }
      #loadingCanvas, #canvas { position: fixed; left: 0; top: 0; display: block; }
      #canvas { visibility: hidden; }
      #start { position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center;
        justify-content: center; gap: 18px; background: #0B0920; color: #A8F6FF; z-index: 10;
        font: 600 22px system-ui, sans-serif; text-align: center; }
      #start img { width: 120px; height: 120px; }
      #start button { font: 700 26px system-ui, sans-serif; padding: 16px 44px; border-radius: 16px;
        border: 4px solid #1B1830; background: #4DEBFF; color: #1B1830; }
      #err { display: none; position: fixed; left: 50%; top: 50%; transform: translate(-50%, -50%); z-index: 30;
        width: min(86vw, 560px); padding: 18px 20px; border-radius: 16px; background: #1B1830; border: 3px solid #FF4D5E;
        color: #F4F6FB; font: 15px system-ui, sans-serif; text-align: center; }
      #err b { color: #FF4D5E; font-size: 19px; } #err code { display: block; margin: 10px 0; color: #FFD84D; word-break: break-word; }
      #err button { font: 700 17px system-ui, sans-serif; padding: 8px 22px; border-radius: 10px; border: 0; background: #4DEBFF; }
      #start small { color: #8E98B3; font-weight: 400; font-size: 15px; padding: 0 20px; }
      #rotate { display: none; position: fixed; inset: 0; z-index: 20; background: #0B0920; color: #A8F6FF;
        font: 600 24px system-ui, sans-serif; text-align: center; align-items: center; justify-content: center;
        flex-direction: column; gap: 16px; }
      #rotate span { font-size: 64px; }
      @media (orientation: portrait) and (pointer: coarse) { #rotate { display: flex; } }
      /* short screens (phones held sideways): a compact start screen */
      @media (max-height: 420px) {
        #start { gap: 8px; font-size: 18px; }
        #start img { width: 64px; height: 64px; }
        #start button { font-size: 20px; padding: 10px 30px; }
        #start small, #iostip { font-size: 12px; }
      }
    </style>
"""

START = """
    <div id="err"><b>Oops! The game hit a problem.</b><code id="errmsg"></code>
      <button onclick="location.reload()">Reload</button></div>
    <div id="rotate"><span>&#x21BB;</span>Turn your phone sideways to play</div>
    <div id="safe"></div>
    <div id="start">
      <img src="icon.png" alt="">
      <div>JUNIOR ASTRONAUT MISSION</div>
      <button id="go">TAP TO PLAY</button>
      <small>Best in landscape. On a phone: left thumb moves, buttons on the right.</small>
      <small id="iostip">iPhone tip: tap Share, then "Add to Home Screen", to play in full screen.</small>
    </div>
"""

FIT = """
      // Fit the 16:9 game canvas as large as possible inside the part of the
      // screen the player can really see: the visual viewport (iPhone Safari
      // toolbars come and go) minus the safe areas (notch, home bar).
      function safeInsets() {
        var el = document.getElementById("safe");
        if (!el) return { t: 0, r: 0, b: 0, l: 0 };
        var cs = getComputedStyle(el);
        return { t: parseFloat(cs.paddingTop) || 0, r: parseFloat(cs.paddingRight) || 0,
                 b: parseFloat(cs.paddingBottom) || 0, l: parseFloat(cs.paddingLeft) || 0 };
      }
      function screenBox() {
        var vv = window.visualViewport;
        var w = vv ? vv.width : window.innerWidth, h = vv ? vv.height : window.innerHeight;
        var x = vv ? vv.offsetLeft : 0, y = vv ? vv.offsetTop : 0;
        var i = safeInsets();
        return { x: x + i.l, y: y + i.t, w: Math.max(1, w - i.l - i.r), h: Math.max(1, h - i.t - i.b) };
      }
      var lastFit = "";
      function fitCanvas() {
        var b = screenBox();
        var s = Math.min(b.w / 1280, b.h / 720);
        var cw = Math.floor(1280 * s), ch = Math.floor(720 * s);
        var left = Math.floor(b.x + (b.w - cw) / 2), top = Math.floor(b.y + (b.h - ch) / 2);
        var key = cw + "," + ch + "," + left + "," + top;
        ["canvas", "loadingCanvas"].forEach(function (id) {
          var c = document.getElementById(id);
          if (!c) return;
          // the engine may reset the size when it starts: re-apply if changed
          if (key === lastFit && c.style.width === cw + "px" && c.style.left === left + "px") return;
          c.style.width = cw + "px"; c.style.height = ch + "px";
          c.style.left = left + "px"; c.style.top = top + "px";
        });
        lastFit = key;
      }
      window.addEventListener("resize", fitCanvas);
      if (window.visualViewport) {
        window.visualViewport.addEventListener("resize", fitCanvas);
        window.visualViewport.addEventListener("scroll", fitCanvas);
      }
      window.addEventListener("orientationchange", function () { setTimeout(fitCanvas, 300); setTimeout(fitCanvas, 900); });
      setInterval(fitCanvas, 400);
      // no page scrolling, pinch zoom or double-tap zoom on phones
      document.addEventListener("touchmove", function (e) { e.preventDefault(); }, { passive: false });
      ["gesturestart", "gesturechange", "gestureend"].forEach(function (n) {
        document.addEventListener(n, function (e) { e.preventDefault(); }, { passive: false });
      });
      var lastTouchEnd = 0;
      document.addEventListener("touchend", function (e) {
        var now = Date.now();
        if (now - lastTouchEnd < 300 && e.target && e.target.tagName !== "BUTTON") e.preventDefault();
        lastTouchEnd = now;
      }, { passive: false });
      // iPhone / iPad Safari cannot go full screen from a page: suggest the
      // Home Screen (which opens the game full screen) unless already there
      document.addEventListener("DOMContentLoaded", function () {
        var ios = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
          (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
        var standalone = window.navigator.standalone === true ||
          (window.matchMedia && window.matchMedia("(display-mode: standalone)").matches);
        var tip = document.getElementById("iostip");
        if (tip && ios && !standalone) tip.style.display = "block";
      });
"""


LOADING = """function drawLoadingText(text) {
        var c = loadingContext.canvas;
        loadingContext.fillStyle = "#0B0920";
        loadingContext.fillRect(0, 0, c.width, c.height);
        loadingContext.textAlign = "center";
        loadingContext.fillStyle = "#4DEBFF";
        loadingContext.font = "bold 56px system-ui, sans-serif";
        loadingContext.fillText("JUNIOR ASTRONAUT MISSION", c.width / 2, c.height / 2 - 40);
        loadingContext.fillStyle = "#A8F6FF";
        loadingContext.font = "32px system-ui, sans-serif";
        var m = /\((\d+)\/(\d+)\)/.exec(text);
        if (m) {
          var f = Number(m[1]) / Math.max(1, Number(m[2]));
          loadingContext.fillText("Loading the Moon base... " + Math.floor(f * 100) + "%", c.width / 2, c.height / 2 + 30);
          loadingContext.fillStyle = "#2F5468"; loadingContext.fillRect(c.width / 2 - 300, c.height / 2 + 70, 600, 22);
          loadingContext.fillStyle = "#5BE37D"; loadingContext.fillRect(c.width / 2 - 300, c.height / 2 + 70, 600 * f, 22);
        } else {
          loadingContext.fillText(text, c.width / 2, c.height / 2 + 30);
        }
      }
"""


SPEECH = """printErr: console.error.bind(console),
        print: function (text) {
          var q = text.indexOf("@@TTSQ@@") === 0, n = text.indexOf("@@TTS@@") === 0;
          if ((q || n) && window.speechSynthesis) {
            var u = new SpeechSynthesisUtterance(text.slice(q ? 8 : 7));
            u.lang = "en-US"; u.rate = 0.95;
            if (n) window.speechSynthesis.cancel();
            window.speechSynthesis.speak(u);
          } else { console.log(text); }
        },"""


def restyle(path):
    s = open(path, encoding="utf-8").read()
    s = s.replace('<link rel="stylesheet" type="text/css" href="theme/love.css">', STYLE)
    s = s.replace('width="800" height="600"', 'width="1280" height="720"')
    # iPhone: draw into the whole screen (notch areas handled by fitCanvas)
    # and do not let the page zoom
    s = s.replace('shrink-to-fit=no, minimum-scale=1, maximum-scale=1"',
                  'shrink-to-fit=no, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover"', 1)
    s = s.replace("<body>", "<body>" + START, 1)
    # show errors on screen (instead of a silent black page) so players can
    # report the exact message
    s = s.replace("""      window.onerror = function(event) {""", """      window.onerror = function(event) {
        try {
          document.getElementById("errmsg").textContent = String(event).slice(0, 300);
          document.getElementById("err").style.display = "block";
        } catch (e) {}""", 1)
    # a clean, on-brand loading screen (the stock one draws at the wrong scale)
    a = s.index("function drawLoadingText(text) {")
    b = s.index("window.onload")
    s = s[:a] + LOADING + "\n      " + s[b:]
    s = s.replace("<script type='text/javascript'>", "<script type='text/javascript'>" + FIT, 1)
    # read-aloud: the game prints "@@TTS@@text" (or "@@TTSQ@@" = queue it)
    s = s.replace("printErr: console.error.bind(console),", SPEECH, 1)
    # start the game only after a tap (unlocks audio on phones), go fullscreen
    s = s.replace("""      var applicationLoad = function(e) {
        Love(Module);
      }""", """      var loveReady = false, tapped = false;
      function boot() {
        if (!(loveReady && tapped)) return;
        // no sound device in this browser? start the game silently instead
        // of letting LOVE fail to open audio (see conf.lua)
        var A = window.AudioContext || window.webkitAudioContext;
        var audioOk = false;
        try { if (A) { var ac = new A(); audioOk = true; if (ac.close) ac.close(); } } catch (err) {}
        if (!audioOk) Module.arguments.push("--noaudio");
        fitCanvas();
        Love(Module);
      }
      var applicationLoad = function(e) { loveReady = true; boot(); };
      document.getElementById("go").addEventListener("click", function () {
        tapped = true;
        document.getElementById("start").style.display = "none";
        try { goFullScreen(); } catch (err) {}
        boot();
      });""")
    s = s.replace("""        if(canvas.requestFullScreen)""", """        canvas = document.documentElement;
        if(canvas.requestFullscreen)
            canvas.requestFullscreen();
        else if(canvas.requestFullScreen)""")
    open(path, "w", encoding="utf-8").write(s)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    out = os.path.abspath(sys.argv[1])
    lovejs = sys.argv[2] if len(sys.argv) > 2 else None
    os.makedirs(out, exist_ok=True)
    love_path = os.path.join(out, "..", "game.love")
    size = pack(love_path)
    print(f"game.love {size / 1e6:.1f} MB")
    if os.path.isdir(out):
        shutil.rmtree(out)
    cmd = ["node", lovejs] if lovejs else ["npx", "love.js"]
    cmd += ["-c", "-t", "Junior Astronaut Mission", "-m", "134217728", love_path, out]
    subprocess.run(cmd, check=True, shell=(os.name == "nt" and not lovejs))
    restyle(os.path.join(out, "index.html"))
    icon = os.path.join(ROOT, "assets", "icon.png")
    if os.path.exists(icon):
        shutil.copy(icon, os.path.join(out, "icon.png"))
    print("web build ->", out)


if __name__ == "__main__":
    main()
