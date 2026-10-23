"""Local task-plan scoring. The imported JSON is data, never executable instructions."""
import json
import math
import re
from collections import Counter
from datetime import date, timedelta
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / 'interleaved-source.json'
STATUSES = ('Not completed', 'In Progress', 'Completed')
TASK_COLUMNS = (('Subject A morning', 'Subject A'), ('Subject B morning', 'Subject B'),
                ('14:00 A output', 'A output'), ('15:15 B output', 'B output'),
                ('Review / CA / writing', 'Review'))
STOP = set('a an the and or of to in on for from with by as at is are was were be been i my we our this that it its then after before only some few one two work worked task tasks done completed complete study studied learning learn'.split())
ALIASES = {'fractions': 'fraction', 'decimals': 'decimal', 'problems': 'problem',
           'questions': 'question', 'mcqs': 'mcq', 'answers': 'answer',
           'reviewed': 'review', 'revision': 'review', 'revised': 'review',
           'practiced': 'practice', 'practised': 'practice', 'recalling': 'recall',
           'recalled': 'recall', 'explained': 'explain', 'corrected': 'correct',
           'correction': 'correct', 'errors': 'error', 'articles': 'article'}


def tokens(text):
    return {ALIASES.get(t, t) for t in re.findall(r'[a-z0-9]+', text.lower())
            if t not in STOP and (len(t) > 1 or t.isdigit())}


def evidence_tokens(text):
    # Conservative: don't count statements explicitly saying work wasn't done,
    # or future plans. This is a documented heuristic, not semantic inference.
    clauses = re.split(r'[;\n]+|(?<!\d)\.(?!\d)|\bbut\b', text.lower())
    negation = r"\b(no|not|never|didn't|haven't|didn’t|haven’t|unfinished|pending|will|plan to|going to)\b"
    return set().union(*(tokens(c) for c in clauses if not re.search(negation, c)))


def load_plan(path=SOURCE):
    raw = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    rows = raw['daily']
    header_index = next(i for i, row in enumerate(rows) if row and row[0] == 'Date')
    header = rows[header_index]
    plan = {}
    for row in rows[header_index + 1:]:
        if not row or isinstance(row[0], bool) or not isinstance(row[0], (int, float)):
            continue
        fields = dict(zip(header, row))
        day = (date(1899, 12, 30) + timedelta(days=int(row[0]))).isoformat()
        tasks = [{'id': str(i), 'label': label, 'text': str(fields[column]).strip()}
                 for i, (column, label) in enumerate(TASK_COLUMNS)
                 if fields.get(column) and str(fields[column]).strip()]
        plan[day] = {'date': day, 'phase': fields.get('Phase', ''), 'tasks': tasks,
                     'planned_hours': float(fields.get('UPSC h') or 0),
                     'schedule_note': fields.get('Test timing override') or ''}
    if not plan:
        raise ValueError('Source contains no daily plan rows')
    return plan


class Scorer:
    def __init__(self, plan):
        self.plan = plan
        documents = [tokens(t['text']) for day in plan.values() for t in day['tasks']]
        frequency = Counter(term for doc in documents for term in doc)
        self.weights = {t: 1 + math.log((1 + len(documents)) / (1 + n))
                        for t, n in frequency.items()}

    def score(self, day, status, hours, description):
        if day not in self.plan:
            raise ValueError('No plan exists for this date')
        if status not in STATUSES:
            raise ValueError('Choose a valid task status')
        if isinstance(hours, bool) or not isinstance(hours, (int, float)) or not math.isfinite(hours) or not 0 <= hours <= 24:
            raise ValueError('Total hours must be a number between 0 and 24')
        if not isinstance(description, str) or not 1 <= len(description.strip()) <= 5000:
            raise ValueError('Describe your work in 1–5000 characters')
        if status != 'Not completed' and hours <= 0:
            raise ValueError('Enter hours spent for work in progress or completed')
        source = self.plan[day]
        evidence = evidence_tokens(description)
        details = []
        for task in source['tasks']:
            terms = tokens(task['text'])
            matched = terms & evidence
            total = sum(self.weights.get(t, 1) for t in terms)
            coverage = sum(self.weights.get(t, 1) for t in matched) / total if total else 0
            details.append({**task, 'coverage': round(coverage * 100, 1), 'matched_terms': sorted(matched)})
        coverage = sum(d['coverage'] for d in details) / len(details) / 100 if details else 0
        planned = source['planned_hours']
        hour_ratio = min(hours / planned, 1) if planned > 0 else 0
        # Hours alone cannot earn points when the description matches no task.
        score = 100 * coverage * (0.7 + 0.3 * hour_ratio)
        if status == 'Not completed' or planned == 0:
            score = 0
        if status == 'In Progress':
            score = min(score, 99)
        return {'score': round(min(score, 100), 1), 'coverage': round(coverage * 100, 1),
                'hours_progress': round(hour_ratio * 100, 1), 'breakdown': details,
                'scoring_version': 'local-v1',
                'explanation': 'Task text coverage × (70% + 30% of planned hours). Not completed = 0%; In Progress is capped at 99%. Zero-hour days are unscored. Text matching is an estimate; paraphrases may be missed.'}
