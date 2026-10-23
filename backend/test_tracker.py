import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from http.server import ThreadingHTTPServer
from scoring import SOURCE, Scorer, load_plan
from server import TrackerStore, handler_for


class TrackerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = TrackerStore(database=Path(self.temp.name) / 'test.sqlite3')
        self.day = '2026-10-23'
        self.source = self.store.plan[self.day]
        self.text = '; '.join(t['text'] for t in self.source['tasks'])

    def tearDown(self):
        self.temp.cleanup()

    def payload(self, **changes):
        return dict({'date': self.day, 'status': 'Completed', 'hours': 8, 'description': self.text}, **changes)

    def test_source_dates_and_full_match(self):
        self.assertEqual(min(self.store.plan), '2026-10-20')
        self.assertEqual(max(self.store.plan), '2027-08-20')
        self.assertEqual(self.store.save(self.payload())['result']['score'], 100)
        self.assertEqual(self.store.plan[self.day]['planned_hours'], 8)

    def test_unrelated_text_and_negation(self):
        for text in ['Watched a movie and cooked dinner', 'I did not cover ' + self.text.replace(';', ',')]:
            self.assertEqual(self.store.save(self.payload(description=text))['result']['score'], 0)

    def test_status_hours_and_bounds(self):
        self.assertEqual(self.store.save(self.payload(status='Not completed'))['result']['score'], 0)
        self.assertEqual(self.store.save(self.payload(status='In Progress'))['result']['score'], 99)
        self.assertEqual(self.store.save(self.payload(hours=4))['result']['score'], 85)
        for hours in [-1, 25, float('nan'), float('inf'), True, '8']:
            with self.assertRaises(ValueError): self.store.save(self.payload(hours=hours))
        for changes in [{'status': 'invalid'}, {'description': ''}, {'description': 'x' * 5001}, {'date': '2020-01-01'}, {'hours': 0}]:
            with self.assertRaises(ValueError): self.store.save(self.payload(**changes))

    def test_replace_persist_and_no_source_mutation(self):
        original = SOURCE.read_bytes()
        self.store.save(self.payload(hours=2))
        self.store.save(self.payload(hours=4))
        other = TrackerStore(database=self.store.database)
        self.assertEqual(other.summary()['logged_hours'], 4)
        self.assertEqual(other.summary()['updated_days'], 1)
        self.assertEqual(other.day(self.day)['update']['hours'], 4)
        self.assertEqual(SOURCE.read_bytes(), original)

    def test_zero_hour_days_and_missing_updates(self):
        day = next(d for d, v in self.store.plan.items() if v['planned_hours'] == 0)
        self.assertEqual(self.store.save(self.payload(date=day))['result']['score'], 0)
        self.assertIsNone(self.store.day(self.day)['update'])
        self.assertEqual(self.store.summary()['score'], 0)

    def test_http_roundtrip_and_validation(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler_for(self.store))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            with urlopen(base + '/api/plan') as response:
                self.assertIn(self.day, json.load(response)['dates'])
            request = Request(base + '/api/update', data=json.dumps(self.payload()).encode(), headers={'Content-Type': 'application/json'})
            with urlopen(request) as response:
                self.assertEqual(json.load(response)['result']['score'], 100)
            with urlopen(base + '/api/day?date=' + self.day) as response:
                self.assertEqual(json.load(response)['update']['hours'], 8)
            with self.assertRaises(HTTPError) as error:
                urlopen(Request(base + '/api/update', data=b'{}', headers={'Content-Type': 'application/json'}))
            self.assertEqual(error.exception.code, 400)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
