#!/usr/bin/env python3
"""
StoneGate - Game distribution server.
Serves the game list and .love files over HTTP for local-network devices.

Usage:
    python server.py [PORT]

Just drop .love files in the games/ directory and they'll appear in the list.
Or use the upload API: POST /games/upload with multipart/form-data.
"""

import hashlib
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
    """Extract metadata from a .love (zip) file.

    Preferred source is a meta.json bundled in the game's root (shipped by the
    game author alongside conf.lua/main.lua). If absent, we fall back to the
    game title parsed out of conf.lua and a default version — so old .love files
    with no meta.json keep working unchanged.
    """
    meta = {
        "name": love_path.stem.replace("_", " ").title(),
        "version": "1.0",
        "author": "",
        "description": "",
    }
    try:
        with zipfile.ZipFile(love_path) as zf:
            names = zf.namelist()

            # 1) meta.json — the authoritative source when present.
            #    Accept it at the archive root ("meta.json") or one level deep
            #    (some packers wrap everything in a top folder).
            meta_name = None
            for name in names:
                base = name.rsplit("/", 1)[-1]
                depth = name.strip("/").count("/")
                if base == "meta.json" and depth <= 1:
                    meta_name = name
                    break
            if meta_name:
                try:
                    data = json.loads(zf.read(meta_name).decode("utf-8"))
                    for key in ("name", "version", "author", "description"):
                        if data.get(key):
                            meta[key] = str(data[key])
                    return meta
                except Exception:
                    pass  # malformed meta.json — fall through to conf.lua

            # 2) Fallback: pull a window title out of conf.lua.
            for name in names:
                if name.endswith("conf.lua"):
                    conf = zf.read(name).decode("utf-8", errors="ignore")
                    for line in conf.splitlines():
                        line = line.strip()
                        # t.window.title = "My Game"  /  t.title = "My Game"
                        if "title" in line and "=" in line and "t.version" not in line:
                            val = line.split("=", 1)[1].strip().strip(",").strip('"').strip("'")
                            if val and not val.startswith("t"):
                                meta["name"] = val
    except Exception:
        pass
    return meta


def sha256_of(path: Path) -> str:
    """Stream-hash a file, returning the lowercase hex digest."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


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
            "id":          game_id,
            "name":        meta["name"],
            "version":     meta["version"],
            "author":      meta["author"],
            "description": meta["description"],
            "file":        f"/games/{love_file.name}",
            "size":        stat.st_size,
            "sha256":      sha256_of(love_file),
            "thumbnail":   thumb if (GAMES_DIR / f"{game_id}.png").exists() else None,
            "updated":     datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d"),
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
        # Strip any path components — a malicious client could send
        # "../../x.love" to escape games/. basename + an explicit ".." reject
        # keeps every upload inside GAMES_DIR.
        filename = os.path.basename(filename.replace("\\", "/"))
        if not filename or filename.startswith("..") or "/" in filename:
            _json_response(self, 400, {"error": "Invalid filename"})
            return
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
                f.write(file_item.data)

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
                    "author": meta["author"],
                    "description": meta["description"],
                    "file": f"/games/{filename}",
                    "size": file_size,
                    "sha256": sha256_of(dest),
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
    """Package the bundled sample/ template into sample.love.

    sample/ is a checked-in template project (conf.lua + main.lua + meta.json +
    assets/) that shows how to write a game for StoneGate. We zip the whole
    directory tree so the produced sample.love carries its meta.json and assets,
    making it a live, end-to-end example of the publish flow.
    """
    sample_dir = GAMES_DIR / "sample"
    sample_love = GAMES_DIR / "sample.love"

    if not sample_dir.is_dir():
        return  # no template source — nothing to package

    # Rebuild if the .love is missing or any source file is newer than it.
    src_files = [p for p in sample_dir.rglob("*") if p.is_file()]
    if not src_files:
        return
    if sample_love.exists():
        newest = max(p.stat().st_mtime for p in src_files)
        if sample_love.stat().st_mtime >= newest:
            return

    with zipfile.ZipFile(sample_love, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in src_files:
            zf.write(p, p.relative_to(sample_dir).as_posix())
    print(f"[stonegate] Packaged sample game: {sample_love} ({len(src_files)} files)")


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
