"""Single-user local API, using only Python's standard library."""
import argparse
import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from scoring import SOURCE, Scorer, load_plan


class TrackerStore:
    def __init__(self, source=SOURCE, database=None):
        self.plan = load_plan(source)
        self.scorer = Scorer(self.plan)
        self.database = str(database or Path(__file__).with_name('tracker.sqlite3'))
        with self.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS updates (day TEXT PRIMARY KEY, status TEXT NOT NULL, hours REAL NOT NULL, description TEXT NOT NULL, updated_at TEXT NOT NULL)')

    @contextmanager
    def connect(self):
        connection = sqlite3.connect(self.database, timeout=10)
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def day(self, day):
        if day not in self.plan:
            raise KeyError('No plan exists for this date')
        with self.connect() as db:
            row = db.execute('SELECT status, hours, description, updated_at FROM updates WHERE day=?', (day,)).fetchone()
        update = dict(zip(('status', 'hours', 'description', 'updated_at'), row)) if row else None
        result = self.scorer.score(day, row[0], row[1], row[2]) if row else None
        return {**self.plan[day], 'update': update, 'result': result}

    def summary(self):
        with self.connect() as db:
            rows = db.execute('SELECT day, status, hours, description FROM updates').fetchall()
        planned_hours = sum(d['planned_hours'] for d in self.plan.values())
        earned = sum(self.scorer.score(day, status, hours, text)['score'] * self.plan[day]['planned_hours']
                     for day, status, hours, text in rows if day in self.plan)
        return {'score': round(earned / planned_hours, 1) if planned_hours else 0,
                'planned_hours': planned_hours, 'logged_hours': sum(r[2] for r in rows if r[0] in self.plan),
                'updated_days': sum(r[0] in self.plan for r in rows), 'total_days': len(self.plan)}

    def save(self, payload):
        if not isinstance(payload, dict):
            raise ValueError('Expected a JSON object')
        day, status, hours, description = (payload.get(k) for k in ('date', 'status', 'hours', 'description'))
        if not isinstance(day, str):
            raise ValueError('Date is required')
        self.scorer.score(day, status, hours, description)
        with self.connect() as db:
            db.execute('INSERT INTO updates VALUES (?, ?, ?, ?, ?) ON CONFLICT(day) DO UPDATE SET status=excluded.status, hours=excluded.hours, description=excluded.description, updated_at=excluded.updated_at',
                       (day, status, hours, description.strip(), datetime.now(timezone.utc).isoformat()))
        return {**self.day(day), 'summary': self.summary()}


def handler_for(store):
    class Handler(BaseHTTPRequestHandler):
        def respond(self, status, data):
            body = json.dumps(data, allow_nan=False).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            url = urlparse(self.path)
            try:
                if url.path == '/api/plan':
                    self.respond(200, {'dates': sorted(store.plan), 'summary': store.summary()})
                elif url.path == '/api/day':
                    day = parse_qs(url.query).get('date', [''])[0]
                    self.respond(200, {**store.day(day), 'summary': store.summary()})
                else:
                    self.respond(404, {'error': 'Endpoint not found'})
            except KeyError as error:
                self.respond(404, {'error': str(error.args[0])})
            except Exception:
                self.respond(500, {'error': 'Could not read tracker data'})

        def do_POST(self):
            if self.path != '/api/update':
                self.respond(404, {'error': 'Endpoint not found'})
                return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 32768:
                    raise ValueError('Request must contain at most 32 KB of JSON')
                if self.headers.get_content_type() != 'application/json':
                    raise ValueError('Content-Type must be application/json')
                self.respond(200, store.save(json.loads(self.rfile.read(length))))
            except (ValueError, TypeError, UnicodeDecodeError) as error:
                self.respond(400, {'error': str(error)})
            except Exception:
                self.respond(500, {'error': 'Could not save tracker update'})

        def log_message(self, fmt, *args):
            pass  # Don't log task descriptions or request contents.
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8000)
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--database', type=Path, default=Path(__file__).with_name('tracker.sqlite3'))
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), handler_for(TrackerStore(args.source, args.database)))
    print(f'Tracker API listening on http://{args.host}:{args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
