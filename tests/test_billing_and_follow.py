import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from decimal import Decimal

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from monitor import UsageReader, valid_usage
from billing import BillingLedger, estimate_request
from active_chat import ActiveChat

def usage(i=100000,c=75000,o=10000,w=0):
    return valid_usage(dict(input_tokens=i,cached_input_tokens=c,output_tokens=o,cache_write_input_tokens=w,reasoning_output_tokens=3000))

class PriceTests(unittest.TestCase):
    def test_cache_and_reasoning_are_not_double_billed(self):
        self.assertEqual(estimate_request('gpt-6-astra',usage()),Decimal('.825'))
    def test_fast_and_flex(self):
        self.assertEqual(estimate_request('gpt-6-astra',usage(),'priority'),Decimal('1.65'))
        self.assertEqual(estimate_request('gpt-6-astra',usage(),'flex'),Decimal('.4125'))
    def test_cache_write_separate_from_regular_input(self):
        self.assertEqual(estimate_request('gpt-6-astra',usage(w=10000)),Decimal('.85'))
        self.assertEqual(estimate_request('gpt-6-astra',usage(w=10000),retention='12h'),Decimal('.975'))
    def test_long_context_is_decided_per_request(self):
        self.assertEqual(estimate_request('gpt-6-astra',usage(i=272000,c=0,o=0)),Decimal('2.72'))
        self.assertEqual(estimate_request('gpt-6-astra',usage(i=272001,c=0,o=0)),Decimal('5.44002'))
    def test_unknown_model_or_tier_stays_unpriced(self):
        self.assertIsNone(estimate_request('invented-astra',usage()))
        self.assertIsNone(estimate_request('gpt-6-astra',usage(),'unknown'))
    def test_models_have_distinct_cache_prices(self):
        self.assertEqual(estimate_request('gpt-6.1-sol',usage()),Decimal('.1575'))
        self.assertEqual(estimate_request('gpt-6-sol',usage()),Decimal('.165'))

class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.l=BillingLedger();self.l.context({'turn_id':'a','model':'gpt-6-astra'})
    def test_canonical_dedup_and_two_equal_responses(self):
        for rid in ('r1','r1','r2'):
            self.l.add({'response_id':rid,'turn_id':'a'},usage(),'stamp')
        self.assertEqual(self.l.snapshot()['requests'],2)
        self.assertAlmostEqual(self.l.snapshot()['cost_usd'],1.65)
    def test_legacy_then_direct_does_not_duplicate(self):
        self.l.add({'total_token_usage':{'total_tokens':110000}},usage(),'stamp',False)
        self.l.add({'response_id':'r'},usage(),'stamp')
        self.l.add({'total_token_usage':{'total_tokens':110000}},usage(),'stamp',False)
        self.assertEqual(self.l.snapshot()['requests'],1)
    def test_legacy_only_turns_and_model_switch(self):
        self.l.add({'total_token_usage':{'total_tokens':110000}},usage(),'s',False)
        self.l.context({'turn_id':'b','model':'gpt-6.1-sol'})
        self.l.add({'response_id':'r2'},usage(),'s')
        s=self.l.snapshot();self.assertEqual(len(s['models']),2);self.assertAlmostEqual(s['cost_usd'],.9825)
    def test_late_response_uses_its_own_turn_model(self):
        self.l.context({'turn_id':'b','model':'gpt-6.1-sol'})
        self.l.add({'response_id':'r','turn_id':'a'},usage(),'s')
        self.assertEqual(self.l.snapshot()['models'][0]['model'],'gpt-6-astra')
    def test_unknown_model_keeps_tokens_but_not_zero_price(self):
        self.l.context({'turn_id':'b','model':'unlisted'})
        self.l.add({'response_id':'r'},usage(),'s')
        s=self.l.snapshot();self.assertTrue(s['partial']);self.assertIsNone(s['cost_usd']);self.assertEqual(s['total_tokens'],110000)
    def test_compaction_preserves_conversation_totals(self):
        r=UsageReader('unused');r.consume({'type':'turn_context','payload':{'turn_id':'a','model':'gpt-6-astra'}})
        r.consume({'type':'token_usage_record','timestamp':'2026-11-06T01:00:00Z','payload':{'response_id':'r','usage':usage()}})
        r.consume({'type':'compacted','payload':{}})
        self.assertIsNone(r.snapshot()['usage']);self.assertEqual(r.snapshot()['billing']['total_tokens'],110000)
    def test_full_history_beyond_old_tail_limit_and_incremental_append(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'history.jsonl'
            context={'type':'turn_context','payload':{'turn_id':'a','model':'gpt-6-astra'}}
            record={'type':'token_usage_record','timestamp':'2026-11-06T01:00:00Z','payload':{'response_id':'r1','usage':usage()}}
            p.write_text(json.dumps(context)+'\n'+json.dumps(record)+'\n'+json.dumps({'type':'response_item','payload':{'text':'x'*(9*1024*1024)}})+'\n',encoding='utf8')
            r=UsageReader(p);r.poll();self.assertEqual(r.snapshot()['billing']['requests'],1)
            record['payload']['response_id']='r2'
            with p.open('a',encoding='utf8') as f:f.write(json.dumps(record)+'\n')
            r.poll();r.poll();self.assertEqual(r.snapshot()['billing']['requests'],2)
            p.write_text(json.dumps(context)+'\n'+json.dumps(record)+'\n',encoding='utf8');r.poll()
            self.assertEqual(r.snapshot()['billing']['requests'],1)

class FollowTests(unittest.TestCase):
    A='11111111-1111-4111-8111-111111111111';B='22222222-2222-4222-8222-222222222222'
    def route(self,f,thread,window=1,stamp='2026-11-06T01:00:00.000Z'):
        f.consume(f'{stamp} info IAB_LIFECYCLE received browser sidebar owner sync conversationId=client-new-thread:stale ownerRoutePath={thread} windowId={window}')
    def test_route_wins_over_stale_conversation_id(self):
        f=ActiveChat();self.route(f,'/local/'+self.A);self.assertEqual(f.selection()['thread_id'],self.A)
    def test_new_chat_clears_previous_usage(self):
        f=ActiveChat();self.route(f,'/local/'+self.A);self.route(f,'/',stamp='2026-11-06T01:00:01.000Z');self.assertIsNone(f.selection()['thread_id'])
    def test_current_window_not_latest_background_event(self):
        f=ActiveChat();self.route(f,'/local/'+self.A);self.route(f,'/local/'+self.B,2)
        f.consume('2026-11-06T01:00:02.000Z info rendererWindowAppearance=primary rendererWindowFocused=true rendererWindowId=1')
        self.assertEqual(f.selection()['thread_id'],self.A)
    def test_old_replayed_log_does_not_revert_selection(self):
        f=ActiveChat();self.route(f,'/local/'+self.B,stamp='2026-11-06T01:00:02.000Z');self.route(f,'/local/'+self.A)
        self.assertEqual(f.selection()['thread_id'],self.B)
    def test_other_process_log_is_not_used(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);folder=root/'2026/11/06';folder.mkdir(parents=True)
            line=f'2026-11-06T01:00:00.000Z info IAB_LIFECYCLE received browser sidebar owner sync ownerRoutePath=/local/{self.A} windowId=1\n'
            (folder/'codex-desktop-x-123-t0-i1-a.log').write_text(line)
            f=ActiveChat(root);self.assertIsNone(f.poll(999)['thread_id']);self.assertEqual(f.poll(123)['thread_id'],self.A)

if __name__=='__main__':unittest.main()
