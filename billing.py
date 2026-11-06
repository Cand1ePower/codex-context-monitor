"""Per-response API-price estimate. No account/billing API or network access."""
from collections import defaultdict
from decimal import Decimal
import json
from pathlib import Path
import re

PRICES = json.loads(Path(__file__).with_name('pricing.json').read_text(encoding='utf-8'))
COUNTERS = ('input_tokens', 'cached_input_tokens', 'cache_write_input_tokens', 'output_tokens', 'total_tokens')


def canonical_model(model):
    model = model or 'unknown'
    if model in PRICES['models']:
        return model
    dated = re.sub(r'-\d{4}-\d{2}-\d{2}$', '', model)
    return dated if dated in PRICES['models'] else model


def estimate_request(model, usage, tier=None, retention=None):
    rate = PRICES['models'].get(canonical_model(model))
    if rate is None:
        return None
    multiplier = {None:1, '':1, 'default':1, 'auto':1, 'standard':1, 'priority':2, 'fast':2, 'flex':0.5, 'batch':0.5}.get(tier)
    if tier == 'ultrafast' and canonical_model(model) in ('gpt-6-astra','gpt-6.1-sol'):
        multiplier = 6
    if multiplier is None:
        return None
    inp, cached, out = (usage[k] for k in ('input_tokens','cached_input_tokens','output_tokens'))
    written = usage.get('cache_write_input_tokens', 0)
    if not 0 <= written <= inp - cached:
        return None
    long = inp > rate['long_threshold']
    write_key = 'write_12h' if retention == '12h' else 'write'
    D = lambda x: Decimal(str(x))
    cost = (D(inp-cached-written)*D(rate['input']) + D(cached)*D(rate['cached']) + D(written)*D(rate[write_key])) * (2 if long else 1)
    cost += D(out)*D(rate['output'])*(D('1.5') if long else 1)
    return cost*D(multiplier)/D(1_000_000)


def empty_group(model):
    return dict(model=model, **{k:0 for k in COUNTERS}, requests=0, known_cost=Decimal(0), unpriced=0, assumed_standard=0, assumed_retention=0)


class BillingLedger:
    """Prefer canonical response records per turn; legacy token_count is a fallback.

    Keeping the two sources separate prevents double billing when both occur or
    when a delayed canonical record follows token_count. Compaction never resets
    conversation totals. No messages are retained.
    """
    def __init__(self):
        self.turn = 'unknown-turn'
        self.model = None
        self.tier = None
        self.retention = None
        self.turn_models = {}
        self.turn_options = {}
        self.turns = {}
        self.seen = set()
        self.last_legacy_signature = None
        self.invalid_records = 0

    def context(self, payload):
        self.turn = payload.get('turn_id') or self.turn
        self.model = payload.get('model') or self.model
        self.tier = payload.get('service_tier')
        self.retention = payload.get('prompt_cache_retention')
        self.turn_models[self.turn] = self.model
        self.turn_options[self.turn] = (self.tier, self.retention)

    def add(self, payload, usage, stamp, canonical=True):
        turn = payload.get('turn_id') or self.turn
        model = payload.get('model') or self.turn_models.get(turn) or self.model or 'unknown'
        tier, retention = self.turn_options.get(turn, (self.tier, self.retention))
        tier = payload.get('service_tier', tier)
        retention = payload.get('prompt_cache_retention', retention)
        if canonical:
            identity = payload.get('response_id') or (turn, stamp, tuple(usage[k] for k in COUNTERS))
            if identity in self.seen:
                return
            self.seen.add(identity)
        else:
            total = payload.get('total_token_usage')
            signature = json.dumps(total, sort_keys=True) if total else (turn, tuple(usage[k] for k in COUNTERS))
            if signature == self.last_legacy_signature:
                return
            self.last_legacy_signature = signature
        slot = self.turns.setdefault(turn, {'direct':{}, 'legacy':{}})
        group = slot['direct' if canonical else 'legacy'].setdefault(model, empty_group(model))
        for key in COUNTERS:
            group[key] += usage[key]
        group['requests'] += 1
        cost = estimate_request(model, usage, tier, retention)
        if cost is None:
            group['unpriced'] += 1
        else:
            group['known_cost'] += cost
        group['assumed_standard'] += tier in (None, '', 'auto')
        group['assumed_retention'] += bool(usage['cache_write_input_tokens'] and not retention)

    def snapshot(self):
        combined = {}
        for slot in self.turns.values():
            for model, source in (slot['direct'] or slot['legacy']).items():
                target = combined.setdefault(model, empty_group(model))
                for key in (*COUNTERS, 'requests','known_cost','unpriced','assumed_standard','assumed_retention'):
                    target[key] += source[key]
        rows = []
        for model, row in sorted(combined.items(), key=lambda x:-x[1]['total_tokens']):
            rate = PRICES['models'].get(canonical_model(model))
            row['display_name'] = rate['name'] if rate else ('未知模型' if model == 'unknown' else model)
            row['cost_usd'] = None if row['unpriced'] else float(row['known_cost'])
            row['known_cost_usd'] = float(row.pop('known_cost'))
            rows.append(row)
        partial = self.invalid_records > 0 or any(r['unpriced'] for r in rows)
        return {'models':rows, 'total_tokens':sum(r['total_tokens'] for r in rows),
                'requests':sum(r['requests'] for r in rows), 'partial':partial,
                'cost_usd':None if partial else sum(r['known_cost_usd'] for r in rows),
                'known_cost_usd':sum(r['known_cost_usd'] for r in rows),
                'pricing_date':PRICES['checked_at'], 'pricing_source':PRICES['source'],
                'assumed_standard':any(r['assumed_standard'] for r in rows),
                'assumed_retention':any(r['assumed_retention'] for r in rows)}
