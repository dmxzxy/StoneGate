#!/usr/bin/env python3
"""
StoneGate - Game distribution server.
Serves the game list and .love files over HTTP for local-network devices.

Usage:
    python server.py [PORT]

Just drop .love files in the games/ directory and they'll appear in the list.
Or use the upload API: POST /games/upload with multipart/form-data.
"""

import http.server
import json
import os
import shutil
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse, parse_qs
import email
import email.policy
from io import BytesIO

# Simple multipart parser (cgi.FieldStorage replacement for Python 3.10+)
class _FakeFieldItem:
    def __init__(self, filename, data):
        self.filename = filename
        self.data = data
    def get_filename(self):
        return self.filename

class _FakeFieldStorage:
    def __init__(self, data_dict):
        self._data = data_dict
    def keys(self):
        return self._data.keys()
    def __getitem__(self, key):
        val = self._data[key]
        if isinstance(val, _FakeFieldItem):
            return val
        return val
    def get(self, key, default=None):
        return self._data.get(key, default)

def _parse_multipart(fp, headers, content_length, keep_blank_values=False):
    """Parse multipart/form-data. Returns a dict-like object."""
    content_type = headers.get("Content-Type", "")
    boundary = None
    for part in content_type.split(';'):
        part = part.strip()
        if part.startswith('boundary='):
            boundary = part[9:].strip('"')
            break
    if not boundary:
        return _FakeFieldStorage({})

    data = fp.read(content_length)
    result = {}
    parts = data.split(b'--' + boundary.encode())
    for part in parts:
        part = part.strip()
        if not part or part == b'--':
            continue
        if b'\r\n' in part:
            header_data, body = part.split(b'\r\n\r\n', 1)
        else:
            header_data, body = part.split(b'\n\n', 1)

        # Parse headers
        headers_dict = {}
        for line in header_data.decode().split('\n'):
            if ':' in line:
                k, v = line.split(':', 1)
                headers_dict[k.strip().lower()] = v.strip()

        cd = headers_dict.get('content-disposition', '')
        filename = None
        field_name = None
        for param in cd.split(';'):
            param = param.strip()
            if param.startswith('filename='):
                filename = param[9:].strip('"')
            elif param.startswith('name='):
                field_name = param[5:].strip('"')

        if field_name:
            if filename:
                result[field_name] = _FakeFieldItem(filename, body.rstrip(b'\r\n'))
            else:
                result[field_name] = body.rstrip(b'\r\n').decode()

    return _FakeFieldStorage(result)

GAMES_DIR = Path(__file__).parent / "games"
DOWNLOADS_DIR = Path(__file__).parent / "downloads"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

# ── Auth token for upload/delete API ──────────────────────────────────
# Change this to your own secret. The publish.sh script must use the same token.
AUTH_TOKEN = os.environ.get("STONEGATE_TOKEN", "stonegate2024")


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


def _check_token(handler) -> bool:
    """Validate auth token from query param ?token=xxx or header Authorization: Bearer xxx."""
    parsed = urlparse(handler.path)
    params = parse_qs(parsed.query)
    token = params.get("token", [None])[0]

    if not token:
        auth = handler.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            token = auth[7:]

    return token == AUTH_TOKEN


def _json_response(handler, code: int, data: dict):
    """Send a JSON response."""
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class GameHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler that serves static files + dynamic game list + upload API."""

    def do_GET(self):
        # Dynamic endpoint: game list
        if self.path in ("/games/list.json", "/list.json"):
            games = generate_game_list()
            payload = json.dumps({"games": games}, ensure_ascii=False)
            body = payload.encode("utf-8")

            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        # Everything else: static file serving (games/*.love, thumbnails, etc.)
        super().do_GET()

    def do_POST(self):
        """Upload a .love file to the games/ directory."""
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path == "/games/upload":
            self._handle_upload()
        else:
            _json_response(self, 404, {"error": "Not found"})

    def do_DELETE(self):
        """Delete a game by id."""
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        # DELETE /games/{game_id}
        if path.startswith("/games/"):
            game_id = path[len("/games/"):]
            self._handle_delete(game_id)
        else:
            _json_response(self, 404, {"error": "Not found"})

    def _handle_upload(self):
        """Handle .love file upload via multipart/form-data."""
        if not _check_token(self):
            _json_response(self, 403, {"error": "Invalid or missing token"})
            return

        content_type = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in content_type:
            _json_response(self, 400, {"error": "Expected multipart/form-data"})
            return

        content_length = int(self.headers.get("Content-Length", 0))
        content_type = self.headers.get("Content-Type", "")

        # Parse multipart data
        form = _parse_multipart(self.rfile, self.headers, content_length, keep_blank_values=True)

        # Find the file field
        file_item = None
        for key in form.keys():
            item = form[key]
            if hasattr(item, "filename") and item.get_filename():
                file_item = item
                break

        if file_item is None:
            _json_response(self, 400, {"error": "No file provided. Use form field 'file'."})
            return

        filename = file_item.get_filename()
        if not filename.endswith(".love"):
            _json_response(self, 400, {"error": "File must have .love extension"})
            return

        # Save to games/ directory
        GAMES_DIR.mkdir(exist_ok=True)
        dest = GAMES_DIR / filename

        # Backup existing file if overwriting
        backup = None
        if dest.exists():
            backup = GAMES_DIR / f"{filename}.bak"
            shutil.copy2(dest, backup)

        try:
            with open(dest, "wb") as f:
                f.write(file_item.file.read())

            file_size = dest.stat().st_size
            game_id = dest.stem
            meta = parse_love_metadata(dest)

            print(f"[stonegate] Uploaded: {filename} ({file_size} bytes) -> {meta['name']}")

            _json_response(self, 200, {
                "ok": True,
                "game": {
                    "id": game_id,
                    "name": meta["name"],
                    "version": meta["version"],
                    "file": f"/games/{filename}",
                    "size": file_size,
                },
            })

            # Remove backup on success
            if backup and backup.exists():
                backup.unlink()

        except Exception as e:
            # Restore backup on failure
            if backup and backup.exists():
                shutil.move(str(backup), str(dest))
            _json_response(self, 500, {"error": f"Save failed: {e}"})

    def _handle_delete(self, game_id: str):
        """Delete a game .love file by id."""
        if not _check_token(self):
            _json_response(self, 403, {"error": "Invalid or missing token"})
            return

        # Sanitize game_id — no path traversal
        game_id = game_id.replace("/", "").replace("\\", "").replace("..", "")
        love_path = GAMES_DIR / f"{game_id}.love"

        if not love_path.exists():
            _json_response(self, 404, {"error": f"Game '{game_id}' not found"})
            return

        try:
            love_path.unlink()
            # Also remove thumbnail if present
            thumb = GAMES_DIR / f"{game_id}.png"
            if thumb.exists():
                thumb.unlink()

            print(f"[stonegate] Deleted: {game_id}")
            _json_response(self, 200, {"ok": True, "deleted": game_id})
        except Exception as e:
            _json_response(self, 500, {"error": f"Delete failed: {e}"})

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
    print(f"║   Upload:   POST /games/upload           ║")
    print(f"║   Token:    {AUTH_TOKEN:<28s} ║")
    print(f"╚══════════════════════════════════════════╝")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[stonegate] Stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
