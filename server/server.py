#!/usr/bin/env python3
"""
StoneGate - Game distribution server.
Serves the game list and .love files over HTTP for local-network devices.

Usage:
    python server.py [PORT]

Just drop .love files in the games/ directory and they'll appear in the list.
"""

import http.server
import json
import os
import sys
import zipfile
from datetime import datetime
from pathlib import Path

GAMES_DIR = Path(__file__).parent / "games"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080


def parse_love_metadata(love_path: Path) -> dict:
    """Extract title and version from conf.lua inside a .love file."""
    meta = {
        "name": love_path.stem.replace("_", " ").title(),
        "version": "1.0",
    }
    try:
        with zipfile.ZipFile(love_path) as zf:
            for name in zf.namelist():
                if name.endswith("conf.lua"):
                    conf = zf.read(name).decode("utf-8", errors="ignore")
                    for line in conf.splitlines():
                        line = line.strip()
                        # t.title = "My Game"
                        if "title" in line and "=" in line and "t.version" not in line:
                            val = line.split("=", 1)[1].strip().strip(",").strip('"').strip("'")
                            if val and not val.startswith("t"):
                                meta["name"] = val
                        # t.version = "1.2"  (game version, not LÖVE version)
                        # We look for a comment or a known field
    except Exception:
        pass
    return meta


def generate_game_list() -> list:
    """Scan the games/ directory and build the game list."""
    GAMES_DIR.mkdir(exist_ok=True)
    games = []

    for love_file in sorted(GAMES_DIR.glob("*.love")):
        game_id = love_file.stem
        meta = parse_love_metadata(love_file)

        stat = love_file.stat()
        thumb = f"/games/{game_id}.png"

        games.append({
            "id":        game_id,
            "name":      meta["name"],
            "version":   meta["version"],
            "file":      f"/games/{love_file.name}",
            "size":      stat.st_size,
            "thumbnail": thumb if (GAMES_DIR / f"{game_id}.png").exists() else None,
            "updated":   datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d"),
        })

    return games


class GameHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler that serves static files + dynamic game list."""

    def do_GET(self):
        # Dynamic endpoint: game list
        if self.path in ("/games/list.json", "/list.json"):
            games = generate_game_list()
            payload = json.dumps({"games": games}, ensure_ascii=False)
            body = payload.encode("utf-8")

            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)
            return

        # Everything else: static file serving (games/*.love, thumbnails, etc.)
        super().do_GET()

    def end_headers(self):
        # Add CORS header to all responses
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def log_message(self, fmt, *args):
        # Quieter logging — one line per request
        sys.stderr.write(f"[stonegate] {args[0]}\n")


def build_sample_game():
    """Create a sample .love file if none exist."""
    sample_dir = GAMES_DIR / "sample"
    sample_love = GAMES_DIR / "sample.love"

    if sample_love.exists():
        return

    sample_dir.mkdir(parents=True, exist_ok=True)
    main_lua = sample_dir / "main.lua"
    if not main_lua.exists():
        main_lua.write_text('''-- conf.lua embedded
	local x, y = 200, 300
	local vx, vy = 180, 130
	local r, g, b = 0.3, 0.6, 1.0

	function love.load()
	    love.window.setTitle("Sample Game")
	end

	function love.update(dt)
	    local w, h = love.graphics.getDimensions()
	    x = x + vx * dt
	    y = y + vy * dt
	    if x <= 30 or x >= w - 30 then
	        vx = -vx
	        r, g, b = math.random()*0.8+0.2, math.random()*0.8+0.2, math.random()*0.8+0.2
	    end
	    if y <= 30 or y >= h - 30 then
	        vy = -vy
	        r, g, b = math.random()*0.8+0.2, math.random()*0.8+0.2, math.random()*0.8+0.2
	    end
	    x = math.max(30, math.min(w - 30, x))
	    y = math.max(30, math.min(h - 30, y))
	end

	function love.draw()
	    love.graphics.setBackgroundColor(0.08, 0.10, 0.15)

	    -- Trail effect
	    love.graphics.setColor(0.15, 0.20, 0.30, 0.4)
	    love.graphics.circle("fill", x - vx * 0.02, y - vy * 0.02, 28)

	    -- Ball
	    love.graphics.setColor(r, g, b)
	    love.graphics.circle("fill", x, y, 30)

	    -- Highlight
	    love.graphics.setColor(1, 1, 1, 0.3)
	    love.graphics.circle("fill", x - 8, y - 8, 10)

	    -- Instructions
	    love.graphics.setColor(0.6, 0.6, 0.7)
	    love.graphics.printf("Sample Game - Bouncing Ball\\nPress ESC to return to StoneGate", 20, 20, love.graphics.getWidth() - 40)
	end
''')

    # Package into .love (just a zip)
    with zipfile.ZipFile(sample_love, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(main_lua, "main.lua")
    print(f"[stonegate] Created sample game: {sample_love}")


def main():
    build_sample_game()

    os.chdir(Path(__file__).parent)  # Serve from server/ directory
    server = http.server.HTTPServer(("0.0.0.0", PORT), GameHandler)

    print(f"╔══════════════════════════════════════════╗")
    print(f"║   StoneGate Game Server                  ║")
    print(f"║   http://0.0.0.0:{PORT:<5}                    ║")
    print(f"║   Games: {GAMES_DIR.absolute()}")
    print(f"║   Game list: /games/list.json            ║")
    print(f"╚══════════════════════════════════════════╝")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[stonegate] Stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
