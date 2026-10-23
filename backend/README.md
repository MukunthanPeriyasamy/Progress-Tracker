# Local Tracker backend

Requires Python 3.10+; no third-party Python packages or AI key are needed.

From the Flutter project folder:

```powershell
py -3 backend/server.py
```

On macOS/Linux use `python3 backend/server.py`. This starts a single-user local API on `127.0.0.1:8000`. Keep the process running while using Tracker. The JSON is read from `interleaved-source.json` next to `pubspec.yaml`; the original rows, text, and imported statuses are never modified. User updates start empty and are stored in `backend/tracker.sqlite3` (ignored by Git). Back up that database to preserve your entries.

## Connect Flutter

Android emulator (default):

```powershell
flutter run --dart-define=TRACKER_API_URL=http://10.0.2.2:8000
```

Physical Android phone over USB:

```powershell
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=TRACKER_API_URL=http://127.0.0.1:8000
```

The server stays bound to your computer's loopback interface. Debug Android builds permit local HTTP. Release builds require an HTTPS server URL; this local prototype is not an authenticated or multi-user hosted service. Flutter Web is not a target of this native Android integration.

## Scoring v1

- Excel serial dates in the `daily` table are converted using the 1899-12-30 epoch.
- Each day's two subjects, two output tasks, and review are compared with the work description. Empty task cells are skipped.
- Text is lowercased, common words removed, and a small explicit alias list normalizes terms such as “revised”/“review.” Source terms are weighted by inverse frequency across the plan. Task coverage is the average weighted fraction of matched terms for each task.
- Clauses explicitly containing negation or future intent are excluded conservatively. This does not fully understand natural language; paraphrases may score too low, and keyword-only or copied text can score too high. Inspect the matched-term breakdown. The source and user text are never executed or treated as instructions.
- `score = 100 × coverage × (0.7 + 0.3 × min(hours / planned_hours, 1))`.
- **Not completed** always scores 0. **In Progress** is capped at 99. **Completed** can reach 100 only with full text coverage and planned hours. Selecting Completed alone does not grant points.
- Unrelated descriptions earn 0 even when hours meet the target. Extra hours cannot push a score above 100. Hours must be finite and within 0–24; positive hours are required for In Progress/Completed.
- Zero-hour exam/rest days are displayed but unscored and excluded from overall weighting.
- Overall plan progress averages daily scores weighted by planned hours across the full imported schedule. Missing updates count as zero. It is not a week-to-date score.
- Updates are daily totals: saving again replaces that date's previous status, hours and description. There is no accumulation or double-counting.

## API

- `GET /api/plan`: available dates and full-plan summary.
- `GET /api/day?date=2026-10-23`: planned tasks, latest update, score/breakdown, summary.
- `POST /api/update`: JSON with `date`, `status`, `hours`, `description`; returns recalculated daily and overall progress after persisting.

Example request:

```json
{
  "date": "2026-10-23",
  "status": "In Progress",
  "hours": 3.5,
  "description": "Reviewed Article 15 and enabling provisions. Practised equivalent fractions and decimal comparison."
}
```

Validation errors return HTTP 400; dates without a plan return 404 on reads. Saving is an idempotent upsert by date, so a retry cannot duplicate hours. The current scoring version is returned in every scored result. Stored descriptions are rescored against the current source if the source is deliberately replaced later.

## Verification

```powershell
py -3 -m unittest discover -s backend -v
flutter analyze
flutter test
```

Backend tests cover real HTTP roundtrips, source dates, 100% and zero scores, status caps, invalid inputs, negation, rest days, durable daily replacement, and source immutability. Widget tests cover form validation, saving, prefilling edits, and preserving input after failure.
