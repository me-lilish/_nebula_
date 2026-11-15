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
        -webkit-user-select: none; user-select: none; -webkit-tap-highlight-color: transparent; }
      center > div > h1, footer { display: none; }
      #loadingCanvas, #canvas { position: fixed; left: 0; top: 0; display: block; }
      #canvas { visibility: hidden; }
      #start { position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center;
        justify-content: center; gap: 18px; background: #0B0920; color: #A8F6FF; z-index: 10;
        font: 600 22px system-ui, sans-serif; text-align: center; }
      #start img { width: 120px; height: 120px; }
      #start button { font: 700 26px system-ui, sans-serif; padding: 16px 44px; border-radius: 16px;
        border: 4px solid #1B1830; background: #4DEBFF; color: #1B1830; }
      #start small { color: #8E98B3; font-weight: 400; font-size: 15px; padding: 0 20px; }
      #rotate { display: none; position: fixed; inset: 0; z-index: 20; background: #0B0920; color: #A8F6FF;
        font: 600 24px system-ui, sans-serif; text-align: center; align-items: center; justify-content: center;
        flex-direction: column; gap: 16px; }
      #rotate span { font-size: 64px; }
      @media (orientation: portrait) and (pointer: coarse) { #rotate { display: flex; } }
    </style>
"""

START = """
    <div id="rotate"><span>&#x21BB;</span>Turn your phone sideways to play</div>
    <div id="start">
      <img src="icon.png" alt="">
      <div>JUNIOR ASTRONAUT MISSION</div>
      <button id="go">TAP TO PLAY</button>
      <small>Best in landscape. On a phone: left thumb moves, buttons on the right.</small>
    </div>
"""

FIT = """
      // keep the 16:9 game canvas as big as possible, centred (letterbox)
      function fitCanvas() {
        var w = window.innerWidth, h = window.innerHeight;
        var s = Math.min(w / 1280, h / 720);
        ["canvas", "loadingCanvas"].forEach(function (id) {
          var c = document.getElementById(id);
          c.style.width = Math.floor(1280 * s) + "px";
          c.style.height = Math.floor(720 * s) + "px";
          c.style.left = Math.floor((w - 1280 * s) / 2) + "px";
          c.style.top = Math.floor((h - 720 * s) / 2) + "px";
        });
      }
      window.addEventListener("resize", fitCanvas);
      // the engine resets the canvas size when it starts: keep re-fitting
      setInterval(fitCanvas, 400);
      window.addEventListener("orientationchange", function () { setTimeout(fitCanvas, 300); });
      document.addEventListener("touchmove", function (e) { e.preventDefault(); }, { passive: false });
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


def restyle(path):
    s = open(path, encoding="utf-8").read()
    s = s.replace('<link rel="stylesheet" type="text/css" href="theme/love.css">', STYLE)
    s = s.replace('width="800" height="600"', 'width="1280" height="720"')
    s = s.replace("<body>", "<body>" + START, 1)
    # a clean, on-brand loading screen (the stock one draws at the wrong scale)
    a = s.index("function drawLoadingText(text) {")
    b = s.index("window.onload")
    s = s[:a] + LOADING + "\n      " + s[b:]
    s = s.replace("<script type='text/javascript'>", "<script type='text/javascript'>" + FIT, 1)
    # start the game only after a tap (unlocks audio on phones), go fullscreen
    s = s.replace("""      var applicationLoad = function(e) {
        Love(Module);
      }""", """      var loveReady = false, tapped = false;
      function boot() { if (loveReady && tapped) { fitCanvas(); Love(Module); } }
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
