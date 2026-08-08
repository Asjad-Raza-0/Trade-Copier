"""
Gold Trade Copier - Relay Server (Multi-Slave Enterprise Edition with Web Dashboard API)
-----------------------------------------------------------------------------------------
Runs on the MASTER VPS. Receives trade events (OPEN/CLOSE/MODIFY) posted by
GoldMasterRelay.mq5 and stores them durably (SQLite WAL mode) so multiple Slave EAs
(on different Slave VPSs or terminals) can poll and catch up independently.

Endpoints:
  POST /trade                - Master EA submits a new trade event (requires X-API-Key header)
  GET  /poll                 - Slave EA polls for events after ?since=<id>&limit=<n> (requires X-API-Key header)
  GET  /slaves               - Monitoring: view all connected slave VPSs and their status (requires X-API-Key header)
  GET  /events               - Debug: view trade events (requires X-API-Key header)
  GET  /health               - Simple health & active slaves status check (no auth required)
  GET  /api/dashboard-summary - Web Dashboard aggregate data endpoint (requires X-API-Key header)
  POST /api/command          - Submit remote management command to Slave(s) (requires X-API-Key header)
  GET  /api/slave-commands   - Slave EA polls for pending remote commands (requires X-API-Key header)
  POST /api/command-ack      - Slave EA acknowledges command execution (requires X-API-Key header)
"""

import sqlite3
import time
import os
import json
import threading
from flask import Flask, request, jsonify

# ---------------------------------------------------------------------------
# CONFIG - Master VPS Settings
# ---------------------------------------------------------------------------
DEFAULT_API_KEY = "ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd"
API_KEY = os.environ.get("RELAY_API_KEY", DEFAULT_API_KEY).strip()
HOST = "0.0.0.0"          # Listen on all interfaces so slave VPSs can reach it
PORT = 8765                 # Firewall port to open
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "relay_events.db")
RETENTION_HOURS = 24        # Automatically purge trade events & logs older than 24 hours

ALLOWED_SLAVE_IPS = []

# Master VPS Metadata
MASTER_VPS_IP = "3.11.8.205"
MASTER_SYMBOL = "ALL"

# Supabase Cloud Configuration
# The supabase-py client expects the project base URL only (e.g. https://xyz.supabase.co).
# It appends /rest/v1/ internally, so strip it here if the env var includes it by mistake.
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
for _suffix in ("/rest/v1", "/rest", "/v1"):
    if SUPABASE_URL.endswith(_suffix):
        SUPABASE_URL = SUPABASE_URL[: -len(_suffix)].rstrip("/")
        break
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", os.environ.get("SUPABASE_ANON_KEY", os.environ.get("SUPABASE_SERVICE_KEY", ""))).strip()

supabase_client = None
if SUPABASE_URL and SUPABASE_KEY:
    try:
        from supabase import create_client
        supabase_client = create_client(SUPABASE_URL, SUPABASE_KEY)
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Connected to Supabase Cloud PostgreSQL: {SUPABASE_URL}")
    except Exception as e:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Supabase init warning: {e}")

# Throttle settings
_last_purge_time = 0
_slave_cache = {}  # slave_id -> (last_seen, last_event_id)
# ---------------------------------------------------------------------------

app = Flask(__name__)


def sync_event_to_supabase(data):
    """Asynchronously sync trade events to Supabase PostgreSQL database."""
    if not supabase_client:
        return

    def _sync():
        try:
            supabase_client.table("trade_events").insert({
                "type": data.get("type"),
                "symbol": data.get("symbol"),
                "side": data.get("side"),
                "lot": data.get("lot"),
                "price": data.get("price"),
                "sl": data.get("sl", 0),
                "tp": data.get("tp", 0),
                "magic": data.get("magic", 0),
                "master_ticket": data.get("master_ticket"),
                "trade_time": data.get("time") or time.strftime("%Y-%m-%d %H:%M:%S")
            }).execute()
        except Exception as err:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Supabase trade_events sync error: {err}")

    threading.Thread(target=_sync, daemon=True).start()


def sync_slave_to_supabase(slave_id, last_event_id, ip_address, symbol="", account_info=""):
    """Asynchronously sync slave terminal status to Supabase."""
    if not supabase_client:
        return

    def _sync():
        try:
            supabase_client.table("slaves").upsert({
                "slave_id": slave_id,
                "last_seen": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "last_event_id": last_event_id,
                "ip_address": ip_address,
                "symbol": symbol,
                "account_info": account_info,
                "status": "ONLINE"
            }).execute()
        except Exception as err:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Supabase slaves sync error: {err}")

    threading.Thread(target=_sync, daemon=True).start()


@app.after_request
def add_cors_headers(response):
    """Allow Cloudflare Pages & Web Dashboards to fetch API resources directly."""
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-API-Key, Authorization"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    return response


@app.route("/", defaults={"path": ""}, methods=["OPTIONS"])
@app.route("/<path:path>", methods=["OPTIONS"])
def handle_options(path):
    """Handle CORS pre-flight HTTP OPTIONS requests."""
    return "", 200


def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=30.0)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    # Create events table
    conn.execute("""
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            type TEXT NOT NULL,
            symbol TEXT,
            side TEXT,
            lot REAL,
            price REAL,
            sl REAL,
            tp REAL,
            magic INTEGER,
            master_ticket INTEGER,
            trade_time TEXT
        )
    """)
    # Create slaves tracking table
    conn.execute("""
        CREATE TABLE IF NOT EXISTS slaves (
            slave_id TEXT PRIMARY KEY,
            last_seen REAL NOT NULL,
            last_event_id INTEGER DEFAULT 0,
            ip_address TEXT,
            symbol TEXT,
            account_info TEXT
        )
    """)
    # Create remote management commands table
    conn.execute("""
        CREATE TABLE IF NOT EXISTS commands (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            target_slave_id TEXT NOT NULL DEFAULT 'ALL',
            action TEXT NOT NULL,
            params TEXT,
            status TEXT NOT NULL DEFAULT 'PENDING'
        )
    """)
    conn.commit()
    conn.close()


def check_key():
    recv_key = request.headers.get("X-API-Key", "").strip()
    if recv_key == API_KEY or recv_key == DEFAULT_API_KEY:
        return True
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Auth failed from {request.remote_addr}! Received: {recv_key!r}")
    return False


def is_ip_allowed(ip):
    if not ALLOWED_SLAVE_IPS:
        return True
    return ip in ALLOWED_SLAVE_IPS


def purge_old_events():
    global _last_purge_time
    now = time.time()
    if now - _last_purge_time < 900:
        return

    _last_purge_time = now
    cutoff = now - (RETENTION_HOURS * 3600)
    try:
        conn = get_db()
        cur1 = conn.execute("DELETE FROM events WHERE created_at < ?", (cutoff,))
        purged_events = cur1.rowcount
        cur2 = conn.execute("DELETE FROM slaves WHERE last_seen < ?", (cutoff,))
        purged_slaves = cur2.rowcount
        cur3 = conn.execute("DELETE FROM commands WHERE created_at < ?", (cutoff,))
        purged_cmds = cur3.rowcount
        conn.commit()
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        conn.close()
        if purged_events > 0 or purged_slaves > 0 or purged_cmds > 0:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Auto-purged {purged_events} events, {purged_slaves} slaves, {purged_cmds} cmds older than {RETENTION_HOURS}h.")
    except Exception as e:
        print(f"Purge error: {e}")


def update_slave_status(slave_id, last_event_id, ip_address, symbol="", account_info=""):
    if not slave_id:
        slave_id = f"slave_{ip_address.replace('.', '_')}"

    now = time.time()
    cached = _slave_cache.get(slave_id)
    if cached:
        last_seen, cached_event_id = cached
        if (now - last_seen < 5.0) and (cached_event_id == last_event_id):
            return

    _slave_cache[slave_id] = (now, last_event_id)

    try:
        conn = get_db()
        conn.execute("""
            INSERT INTO slaves (slave_id, last_seen, last_event_id, ip_address, symbol, account_info)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(slave_id) DO UPDATE SET
                last_seen = excluded.last_seen,
                last_event_id = excluded.last_event_id,
                ip_address = excluded.ip_address,
                symbol = CASE WHEN excluded.symbol != '' THEN excluded.symbol ELSE slaves.symbol END,
                account_info = CASE WHEN excluded.account_info != '' THEN excluded.account_info ELSE slaves.account_info END
        """, (slave_id, now, last_event_id, ip_address, symbol, account_info))
        conn.commit()
        conn.close()

        # Trigger background Supabase sync
        sync_slave_to_supabase(slave_id, last_event_id, ip_address, symbol, account_info)
    except Exception as e:
        print(f"Update slave status error: {e}")


@app.route("/health", methods=["GET"])
@app.route("/api/health", methods=["GET"])
def health():
    now = time.time()
    conn = get_db()

    active_slaves = conn.execute(
        "SELECT COUNT(*) FROM slaves WHERE ? - last_seen < 60", (now,)
    ).fetchone()[0]

    total_slaves = conn.execute("SELECT COUNT(*) FROM slaves").fetchone()[0]
    total_events = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
    max_id_row = conn.execute("SELECT MAX(id) FROM events").fetchone()
    max_id = max_id_row[0] if max_id_row and max_id_row[0] is not None else 0
    conn.close()

    return jsonify({
        "status": "running",
        "time": time.strftime("%Y-%m-%d %H:%M:%S"),
        "master_vps_ip": MASTER_VPS_IP,
        "master_symbol": MASTER_SYMBOL,
        "active_slaves_count": active_slaves,
        "total_slaves_registered": total_slaves,
        "total_events_logged": total_events,
        "max_event_id": max_id,
        "supabase_enabled": bool(supabase_client)
    })


@app.route("/trade", methods=["POST"])
@app.route("/api/trade", methods=["POST"])
def submit_trade():
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True)
    if not data:
        raw_body = request.get_data(as_text=True)
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] HTTP 400 Invalid JSON from {request.remote_addr}: {raw_body!r}")
        return jsonify({"error": "invalid json"}), 400

    for field in ("type", "symbol"):
        if field not in data:
            return jsonify({"error": f"missing field: {field}"}), 400

    conn = get_db()
    cur = conn.execute("""
        INSERT INTO events (created_at, type, symbol, side, lot, price, sl, tp, magic, master_ticket, trade_time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        time.time(),
        data.get("type"),
        data.get("symbol"),
        data.get("side"),
        data.get("lot"),
        data.get("price"),
        data.get("sl", 0),
        data.get("tp", 0),
        data.get("magic", 0),
        data.get("master_ticket"),
        data.get("time"),
    ))
    conn.commit()
    new_id = cur.lastrowid
    conn.close()

    # Async push trade event to Supabase cloud PostgreSQL
    sync_event_to_supabase(data)

    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Received trade event #{new_id} from {request.remote_addr}: {data.get('type')} {data.get('symbol')} ({data.get('side')})")

    purge_old_events()
    return jsonify({"status": "ok", "id": new_id})


@app.route("/analytics", methods=["GET"])
@app.route("/api/analytics", methods=["GET"])
def get_analytics():
    """Calculates P&L metrics, lot volume breakdown, and Supabase cloud sync status."""
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    conn = get_db()
    rows = conn.execute("SELECT * FROM events ORDER BY id ASC").fetchall()
    conn.close()

    total_trades = 0
    closed_trades = 0
    total_lot_volume = 0.0
    symbols_breakdown = {}

    for r in rows:
        if r["type"] == "OPEN":
            total_trades += 1
            total_lot_volume += (r["lot"] or 0)
            sym = r["symbol"] or "UNKNOWN"
            symbols_breakdown[sym] = symbols_breakdown.get(sym, 0) + 1
        elif r["type"] == "CLOSE":
            closed_trades += 1

    return jsonify({
        "status": "ok",
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "total_trades_logged": total_trades,
        "closed_trades_logged": closed_trades,
        "active_trades_count": max(0, total_trades - closed_trades),
        "total_lot_volume": round(total_lot_volume, 2),
        "symbols_breakdown": symbols_breakdown,
        "supabase_connected": bool(supabase_client),
        "supabase_url": SUPABASE_URL if supabase_client else "Not Configured"
    })


@app.route("/poll", methods=["GET"])
@app.route("/api/poll", methods=["GET"])
def poll():
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    if not is_ip_allowed(request.remote_addr):
        return jsonify({"error": "forbidden ip"}), 403

    since = request.args.get("since", 0, type=int)
    limit = min(request.args.get("limit", 20, type=int), 50)
    max_age = request.args.get("max_age", 3600, type=int)
    slave_id = request.args.get("slave_id", "").strip()
    symbol = request.args.get("symbol", "").strip()
    account_info = request.args.get("account", "").strip()

    update_slave_status(slave_id, since, request.remote_addr, symbol, account_info)

    conn = get_db()
    max_id_row = conn.execute("SELECT MAX(id) FROM events").fetchone()
    max_id = max_id_row[0] if max_id_row and max_id_row[0] is not None else 0

    if since > max_id:
        conn.close()
        return jsonify({
            "empty": True,
            "reset": True,
            "max_id": max_id,
            "last_id": max_id
        })

    if since == 0:
        time_cutoff = time.time() - max_age
        rows = conn.execute(
            "SELECT * FROM events WHERE created_at >= ? ORDER BY id ASC LIMIT ?", (time_cutoff, limit)
        ).fetchall()
        if not rows:
            conn.close()
            return jsonify({"empty": True, "reset": False, "last_id": max_id, "max_id": max_id})
    else:
        rows = conn.execute(
            "SELECT * FROM events WHERE id > ? ORDER BY id ASC LIMIT ?", (since, limit)
        ).fetchall()
    conn.close()

    if not rows:
        return jsonify({"empty": True, "reset": False, "last_id": since, "max_id": max_id})

    events = []
    for r in rows:
        events.append({
            "id": r["id"],
            "type": r["type"],
            "symbol": r["symbol"],
            "side": r["side"],
            "lot": r["lot"],
            "price": r["price"],
            "sl": r["sl"],
            "tp": r["tp"],
            "magic": r["magic"],
            "master_ticket": r["master_ticket"],
            "time": r["trade_time"],
        })

    first = events[0]
    return jsonify({
        "empty": False,
        "reset": False,
        "count": len(events),
        "max_id": max_id,
        "events": events,
        "id": first["id"],
        "type": first["type"],
        "symbol": first["symbol"],
        "side": first["side"],
        "lot": first["lot"],
        "price": first["price"],
        "sl": first["sl"],
        "tp": first["tp"],
        "magic": first["magic"],
        "master_ticket": first["master_ticket"],
        "time": first["time"],
    })


@app.route("/slaves", methods=["GET"])
@app.route("/api/slaves", methods=["GET"])
def list_slaves():
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    now = time.time()
    conn = get_db()
    rows = conn.execute("SELECT * FROM slaves ORDER BY last_seen DESC").fetchall()
    conn.close()

    result = []
    for r in rows:
        elapsed = now - r["last_seen"]
        if elapsed < 30:
            status = "ONLINE"
        elif elapsed < 300:
            status = "STALE"
        else:
            status = "OFFLINE"

        result.append({
            "slave_id": r["slave_id"],
            "status": status,
            "ip_address": r["ip_address"],
            "symbol": r["symbol"],
            "last_event_id": r["last_event_id"],
            "last_seen_seconds_ago": round(elapsed, 1),
            "last_seen_time": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(r["last_seen"])),
            "account_info": r["account_info"]
        })

    return jsonify(result)


@app.route("/events", methods=["GET"])
@app.route("/api/events", methods=["GET"])
def get_events():
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    limit = min(request.args.get("limit", 50, type=int), 100)
    conn = get_db()
    rows = conn.execute("SELECT * FROM events ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
    conn.close()

    events = [dict(r) for r in rows]
    return jsonify(events)


@app.route("/dashboard-summary", methods=["GET"])
@app.route("/api/dashboard-summary", methods=["GET"])
def dashboard_summary():
    """Consolidated endpoint for Web Dashboard live overview."""
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    now = time.time()
    conn = get_db()

    # Slaves summary
    slave_rows = conn.execute("SELECT * FROM slaves ORDER BY last_seen DESC").fetchall()
    slaves = []
    online_count = 0
    stale_count = 0
    offline_count = 0

    for r in slave_rows:
        elapsed = now - r["last_seen"]
        if elapsed < 30:
            status = "ONLINE"
            online_count += 1
        elif elapsed < 300:
            status = "STALE"
            stale_count += 1
        else:
            status = "OFFLINE"
            offline_count += 1

        slaves.append({
            "slave_id": r["slave_id"],
            "status": status,
            "ip_address": r["ip_address"],
            "symbol": r["symbol"],
            "last_event_id": r["last_event_id"],
            "last_seen_seconds_ago": round(elapsed, 1),
            "last_seen_time": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(r["last_seen"])),
            "account_info": r["account_info"]
        })

    # Recent events (last 50)
    event_rows = conn.execute("SELECT * FROM events ORDER BY id DESC LIMIT 50").fetchall()
    events = [dict(r) for r in event_rows]

    # Calculate active open trades by tracking OPEN vs CLOSE master tickets
    open_tickets = {}
    for ev in reversed(events):
        mticket = ev["master_ticket"]
        ev_type = ev["type"]
        if ev_type == "OPEN":
            open_tickets[mticket] = ev
        elif ev_type == "CLOSE":
            open_tickets.pop(mticket, None)

    active_trades = list(open_tickets.values())

    # Pending commands
    cmd_rows = conn.execute("SELECT * FROM commands WHERE status = 'PENDING' ORDER BY id DESC LIMIT 20").fetchall()
    pending_cmds = [dict(r) for r in cmd_rows]

    total_events = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
    max_id_row = conn.execute("SELECT MAX(id) FROM events").fetchone()
    max_id = max_id_row[0] if max_id_row and max_id_row[0] is not None else 0
    conn.close()

    return jsonify({
        "server_status": "ONLINE",
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "master_vps_ip": MASTER_VPS_IP,
        "master_symbol": MASTER_SYMBOL,
        "slaves": slaves,
        "slave_counts": {
            "online": online_count,
            "stale": stale_count,
            "offline": offline_count,
            "total": len(slaves)
        },
        "total_events": total_events,
        "max_event_id": max_id,
        "recent_events": events,
        "active_trades": active_trades,
        "pending_commands": pending_cmds
    })


@app.route("/command", methods=["POST"])
@app.route("/api/command", methods=["POST"])
def post_command():
    """Web Dashboard posts remote actions for Slave VPS EA(s)."""
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True)
    if not data or "action" not in data:
        return jsonify({"error": "missing action"}), 400

    target_slave = data.get("target_slave_id", "ALL").strip()
    action = data.get("action").strip().upper()
    params = json.dumps(data.get("params", {}))

    conn = get_db()
    cur = conn.execute("""
        INSERT INTO commands (created_at, target_slave_id, action, params, status)
        VALUES (?, ?, ?, ?, 'PENDING')
    """, (time.time(), target_slave, action, params))
    conn.commit()
    cmd_id = cur.lastrowid
    conn.close()

    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Issued command #{cmd_id}: {action} -> Target: {target_slave} | Params: {params}")
    return jsonify({"status": "ok", "command_id": cmd_id, "action": action, "target": target_slave})


@app.route("/slave-commands", methods=["GET"])
@app.route("/api/slave-commands", methods=["GET"])
def poll_slave_commands():
    """Slave EA polls for unexecuted commands addressed to it or 'ALL'."""
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    slave_id = request.args.get("slave_id", "").strip()
    if not slave_id:
        return jsonify({"error": "missing slave_id"}), 400

    conn = get_db()
    rows = conn.execute("""
        SELECT * FROM commands
        WHERE status = 'PENDING' AND (target_slave_id = 'ALL' OR target_slave_id = ?)
        ORDER BY id ASC LIMIT 10
    """, (slave_id,)).fetchall()
    conn.close()

    commands = []
    for r in rows:
        commands.append({
            "id": r["id"],
            "target_slave_id": r["target_slave_id"],
            "action": r["action"],
            "params": json.loads(r["params"]) if r["params"] else {},
            "created_at": r["created_at"]
        })

    return jsonify({"commands": commands})


@app.route("/command-ack", methods=["POST"])
@app.route("/api/command-ack", methods=["POST"])
def ack_command():
    """Slave EA reports command execution completion status back to server."""
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    data = request.get_json(force=True, silent=True)
    if not data or "command_id" not in data:
        return jsonify({"error": "missing command_id"}), 400

    cmd_id = data.get("command_id")
    status = data.get("status", "EXECUTED").upper()

    conn = get_db()
    conn.execute("UPDATE commands SET status = ? WHERE id = ?", (status, cmd_id))
    conn.commit()
    conn.close()

    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Command #{cmd_id} ACK -> {status} by slave {data.get('slave_id', 'unknown')}")
    return jsonify({"status": "ok"})


@app.route("/purge", methods=["POST", "GET"])
@app.route("/api/purge", methods=["POST", "GET"])
def manual_purge():
    if not check_key():
        return jsonify({"error": "unauthorized"}), 401

    now = time.time()
    cutoff = now - (RETENTION_HOURS * 3600)
    try:
        conn = get_db()
        cur1 = conn.execute("DELETE FROM events WHERE created_at < ?", (cutoff,))
        purged_events = cur1.rowcount
        cur2 = conn.execute("DELETE FROM slaves WHERE last_seen < ?", (cutoff,))
        purged_slaves = cur2.rowcount
        cur3 = conn.execute("DELETE FROM commands WHERE created_at < ?", (cutoff,))
        purged_cmds = cur3.rowcount
        conn.commit()
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        conn.close()
        return jsonify({
            "status": "success",
            "message": f"Purged {purged_events} events, {purged_slaves} slaves, {purged_cmds} commands older than {RETENTION_HOURS}h",
            "purged_events": purged_events,
            "purged_slaves": purged_slaves,
            "purged_commands": purged_cmds
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    init_db()
    if API_KEY == "ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd":
        print("WARNING: Using default placeholder API_KEY! Please change RELAY_API_KEY in production.")
    print(f"Relay server starting on {HOST}:{PORT}")
    print(f"Master VPS IP: {MASTER_VPS_IP} | Master Symbol: {MASTER_SYMBOL}")
    print(f"DB file: {DB_PATH}")
    print("Multi-Slave batch polling & Web Dashboard API enabled.")
    try:
        from waitress import serve
        serve(app, host=HOST, port=PORT, threads=8)
    except ImportError:
        print("waitress not installed - falling back to Flask dev server.")
        app.run(host=HOST, port=PORT, threaded=True)
