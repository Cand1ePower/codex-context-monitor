import importlib.util
import json
from pathlib import Path
import tempfile
import sqlite3
import unittest
import sys

source = Path(__file__).resolve().parents[1] / 'monitor.py'
sys.path.insert(0,str(source.parent))
spec = importlib.util.spec_from_file_location('monitor', source)
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


def usage(i=1000, c=750, o=100):
    return dict(input_tokens=i, cached_input_tokens=c, output_tokens=o, reasoning_output_tokens=30)


def event(kind, payload, stamp='2026-01-01T00:00:10.000Z'):
    return dict(type=kind, payload=payload, timestamp=stamp)


class UsageTests(unittest.TestCase):
    def setUp(self):
        self.reader = monitor.UsageReader('not-read.jsonl')
        self.reader.set_window(2000)

    def test_context_includes_cached_input_and_output(self):
        self.reader.consume(event('token_usage_record', dict(usage=usage(), response_id='r1')))
        s = self.reader.snapshot()
        self.assertEqual(s['percent'], 55)
        self.assertEqual(s['cache_percent'], 75)
        self.assertEqual(s['remaining'], 900)

    def test_speed_uses_generation_and_excludes_tool_execution(self):
        end = monitor.stamp_ms('2026-01-01T00:00:10.000Z')
        self.reader.consume(event('event_msg', dict(type='item_completed', item={'type':'McpToolCall'}, started_at_ms=end-40000, completed_at_ms=end-5000)))
        self.reader.consume(event('event_msg', dict(type='item_completed', item={'type':'Reasoning'}, started_at_ms=end-2000, completed_at_ms=end-1000)))
        self.reader.consume(event('token_usage_record', dict(usage=usage(), response_id='r1')))
        self.assertEqual(self.reader.speed, 50)
        self.reader.consume(event('event_msg', dict(type='token_count', info=dict(last_token_usage=usage(), model_context_window=2000)), '2026-01-01T00:00:30Z'))
        self.assertEqual(self.reader.speed, 50)
        self.assertEqual(self.reader.usage_ms, end)
        self.reader.consume(event('token_usage_record', dict(usage=usage(), response_id='r2'), '2026-01-01T00:01:00Z'))
        self.assertIsNone(self.reader.speed)

    def test_unknown_zero_and_invalid(self):
        self.assertIsNone(self.reader.snapshot()['percent'])
        self.assertIsNone(monitor.valid_usage(usage(c=1001)))
        self.assertIsNone(monitor.valid_usage({'input_tokens':5}))
        self.reader.consume(event('token_usage_record', dict(usage=usage(i=0,c=0,o=0), response_id='r1')))
        self.assertIsNone(self.reader.snapshot()['cache_percent'])
        self.assertEqual(self.reader.snapshot()['percent'], 0)

    def test_compaction_clears_previous_sample(self):
        self.reader.consume(event('token_usage_record', dict(usage=usage(), response_id='r1')))
        self.reader.consume(event('compacted', {}))
        self.assertIsNone(self.reader.snapshot()['percent'])
        self.assertTrue(self.reader.compacted)

    def test_partial_lines_and_truncation(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'rollout.jsonl'
            line=json.dumps(event('event_msg',dict(type='token_count',info=dict(last_token_usage=usage(),model_context_window=2000)))).encode()
            p.write_bytes(line[:20])
            r=monitor.UsageReader(p)
            r.poll()
            self.assertIsNone(r.usage)
            with p.open('ab') as f:f.write(line[20:]+b'\n')
            r.poll()
            self.assertEqual(r.snapshot()['percent'],55)
            p.write_bytes(b'{}\n')
            r.poll()
            self.assertIsNone(r.usage)

    def test_snapshot_never_contains_message_content(self):
        secret='private chat content'
        self.reader.consume(event('response_item',dict(type='message',content=secret)))
        self.assertNotIn(secret,json.dumps(self.reader.snapshot()))

    def test_catalog_includes_desktop_chats_without_user_event_flag(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            with sqlite3.connect(home/'state_5.sqlite') as con:
                con.execute('CREATE TABLE threads (id,title,name,rollout_path,model,archived,agent_path,attached_thread_parent_id,source,recency_at_ms)')
                con.executemany('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?,?,?)',[
                    ('root1','raw title','Readable name','a.jsonl','model',0,None,None,'vscode',100),
                    ('root2','second',None,'b.jsonl','model',0,None,None,'vscode',99),
                    ('child','worker',None,'c.jsonl','model',0,'/root/child',None,'subagent',101),
                ])
            con.close()
            threads=monitor.list_threads(home,'root1')
            self.assertEqual([x['id'] for x in threads],['root1','root2'])
            self.assertEqual(threads[0]['title'],'Readable name')

if __name__=='__main__':unittest.main()
