"""Read local Codex usage only. No network, prompt export, or Codex writes."""
from __future__ import annotations

import argparse
from contextlib import closing
import ctypes
import datetime as dt
import json
import os
from pathlib import Path
import sqlite3
import time
import re
from collections import OrderedDict

from active_chat import ActiveChat, read_owner
from billing import BillingLedger


def stamp_ms(value):
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000
    except (TypeError, ValueError, AttributeError):
        return None


def valid_usage(value):
    if not isinstance(value, dict):
        return None
    names = ("input_tokens", "cached_input_tokens", "output_tokens")
    if any(type(value.get(k)) is not int or value[k] < 0 for k in names):
        return None
    if value["cached_input_tokens"] > value["input_tokens"]:
        return None
    result = {k: value[k] for k in names}
    result["total_tokens"] = value["input_tokens"] + value["output_tokens"]
    written = value.get("cache_write_input_tokens", 0)
    if type(written) is not int or not 0 <= written <= value['input_tokens']-value['cached_input_tokens']:
        return None
    result['cache_write_input_tokens'] = written
    reasoning = value.get("reasoning_output_tokens")
    result["reasoning_output_tokens"] = reasoning if type(reasoning) is int and 0 <= reasoning <= value["output_tokens"] else None
    return result


class UsageReader:
    def __init__(self, path, model=None):
        self.path = Path(path)
        self.offset = 0
        self.partial = b""
        self.started = False
        self.model = model
        self.window = None
        self.usage = None
        self.usage_ms = None
        self.pending_start = None
        self.speed = None
        self.speed_ms = None
        self.speed_duration_ms = None
        self.last_response_id = None
        self.last_record_ms = None
        self.running = None
        self.compacted = False
        self.error = None
        self.identity = None
        self.billing = BillingLedger()
        self.history_complete = False
        self.file_size = 0

    def reset_usage(self):
        self.usage = None
        self.usage_ms = None
        self.pending_start = None
        self.speed = None
        self.speed_ms = None
        self.speed_duration_ms = None
        self.last_response_id = None
        self.last_record_ms = None

    def set_window(self, value):
        if type(value) is int and value > 0:
            self.window = value

    def consume(self, event):
        if not isinstance(event, dict):
            return
        kind = event.get("type")
        payload = event.get("payload")
        if not isinstance(payload, dict):
            return
        ts = stamp_ms(event.get("timestamp"))
        subkind = payload.get("type")
        if kind == "session_meta":
            self.set_window(payload.get("context_window"))
        elif kind == "turn_context":
            self.model = payload.get("model") or self.model
            self.billing.context(payload)
        elif kind == "compacted" or subkind == "context_compacted":
            self.reset_usage()
            self.compacted = True
        elif kind == "event_msg" and subkind == "task_started":
            self.running = True
            self.pending_start = None
            self.set_window(payload.get("model_context_window"))
        elif kind == "event_msg" and subkind in ("task_complete", "task_completed", "turn_aborted"):
            self.running = False
            self.pending_start = None
        elif kind == "event_msg" and subkind == "item_completed":
            item = payload.get("item") or {}
            if str(item.get("type", "")).lower() not in ("reasoning", "agentmessage"):
                return
            begin = payload.get("started_at_ms")
            end = payload.get("completed_at_ms")
            # Tool execution intervals are deliberately excluded. Records from
            # already-counted responses must never leak into the next sample.
            if (type(begin) in (int, float) and type(end) in (int, float)
                    and end > begin and (self.last_record_ms is None or begin > self.last_record_ms)):
                self.pending_start = min(self.pending_start, begin) if self.pending_start is not None else begin
        elif kind == "token_usage_record":
            usage = valid_usage(payload.get("usage"))
            if usage is not None:
                self.billing.add(payload, usage, event.get('timestamp'))
            else:
                self.billing.invalid_records += 1
            response_id = payload.get("response_id")
            if usage is None or ts is None or (response_id and response_id == self.last_response_id):
                return
            self.speed = None
            self.speed_duration_ms = None
            if self.pending_start is not None:
                elapsed = ts - self.pending_start
                if 100 <= elapsed <= 3_600_000 and usage["output_tokens"] > 0:
                    self.speed = usage["output_tokens"] * 1000 / elapsed
                    self.speed_duration_ms = elapsed
            self.speed_ms = ts if self.speed is not None else None
            self.pending_start = None
            self.last_response_id = response_id
            self.last_record_ms = ts
            self.usage, self.usage_ms = usage, ts
            self.compacted = False
        elif kind == "event_msg" and subkind == "token_count":
            info = payload.get("info") or {}
            self.set_window(info.get("model_context_window"))
            usage = valid_usage(info.get("last_token_usage"))
            if usage is not None and ts is not None:
                self.billing.add(info, usage, event.get('timestamp'), canonical=False)
                # token_count is often a delayed duplicate of token_usage_record.
                if usage != self.usage:
                    self.speed = self.speed_ms = self.speed_duration_ms = None
                    self.usage, self.usage_ms = usage, ts
                elif self.usage_ms is None:
                    self.usage_ms = ts
                self.compacted = False

    def poll(self):
        try:
            stat = self.path.stat()
            identity = (stat.st_dev, stat.st_ino)
            if self.started and (stat.st_size < self.offset or identity != self.identity):
                self.__init__(self.path, self.model)
            self.identity = identity
            self.file_size = stat.st_size
            with self.path.open("rb") as f:
                if not self.started:
                    # Price totals require the whole transcript. Read bounded
                    # chunks, retain numeric metadata only, then tail increments.
                    self.offset = 0
                    self.started = True
                f.seek(self.offset)
                data = f.read(32 * 1024 * 1024)
                self.offset = f.tell()
            lines = (self.partial + data).split(b"\n")
            self.partial = lines.pop()
            for line in lines:
                # Event type is in the envelope; skip bulky message/tool bodies.
                if not re.search(rb'"type"\s*:\s*"(?:session_meta|turn_context|compacted|event_msg|token_usage_record)"', line[:240]):
                    continue
                try:
                    self.consume(json.loads(line))
                except (ValueError, UnicodeError, TypeError):
                    continue
            self.error = None
            self.history_complete = self.offset >= stat.st_size and not self.partial
        except (OSError, PermissionError):
            self.error = "无法读取该聊天的本地用量记录"

    def snapshot(self, now_ms=None):
        now_ms = now_ms if now_ms is not None else time.time() * 1000
        usage = self.usage
        total = usage["total_tokens"] if usage else None
        return {
            "model": self.model,
            "window": self.window,
            "usage": usage,
            "percent": 100 * total / self.window if total is not None and self.window else None,
            "remaining": max(0, self.window - total) if total is not None and self.window else None,
            "cache_percent": 100 * usage["cached_input_tokens"] / usage["input_tokens"] if usage and usage["input_tokens"] else None,
            "speed_tps": self.speed,
            "speed_kind": "recent_response_estimate" if self.speed is not None else "unavailable",
            "speed_duration_ms": self.speed_duration_ms,
            "sampled_at_ms": self.usage_ms,
            "age_seconds": max(0, int((now_ms - self.usage_ms) / 1000)) if self.usage_ms else None,
            "running": self.running,
            "compacted": self.compacted,
            "error": self.error,
            "billing": self.billing.snapshot(),
            "history_complete": self.history_complete,
            "history_progress": min(1, self.offset/self.file_size) if self.file_size else 1,
        }


def read_selection(path, fallback):
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig")).get("thread_id")
        return value if isinstance(value, str) and len(value) == 36 else fallback
    except (OSError, ValueError):
        return fallback


def list_threads(home, selected):
    database = home / "state_5.sqlite"
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=0.2)) as con:
        rows = con.execute(
            "SELECT id,COALESCE(NULLIF(name,''),title),rollout_path,model FROM threads WHERE "
            "(archived=0 AND COALESCE(agent_path,'') IN ('','/root') "
            "AND attached_thread_parent_id IS NULL AND source NOT LIKE '%subagent%') OR id=? "
            "ORDER BY CASE WHEN id=? THEN 0 ELSE 1 END,recency_at_ms DESC LIMIT 60",
            (selected, selected),
        ).fetchall()
    return [{"id": r[0], "title": (r[1] or r[0])[:100], "path": r[2], "model": r[3]} for r in rows]


def parent_alive(pid):
    if not pid or os.name != "nt":
        return True
    kernel = ctypes.windll.kernel32
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    result = ctypes.c_ulong()
    try:
        return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(result))) and result.value == 259
    finally:
        kernel.CloseHandle(handle)


def atomic_json(path, value):
    tmp = path.with_suffix(".tmp")
    try:
        tmp.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, path)
        return True
    except OSError:
        # Both the temporary write and replacement can hit sharing violations
        # on Windows. Leave the last complete state intact and retry next tick.
        return False


def run(args):
    home = Path(args.codex_home or os.environ.get("CODEX_HOME") or Path.home() / ".codex").resolve()
    runtime = Path(args.runtime).resolve()
    runtime.mkdir(parents=True, exist_ok=True)
    selected = None
    meta = None
    readers = OrderedDict()
    follower = ActiveChat()
    next_meta = 0
    while parent_alive(args.parent_pid):
        # Fixed thread IDs are allowed only for explicit one-shot diagnostics.
        active = ({'thread_id':args.thread_id, 'source':'diagnostic', 'status':'following'}
                  if args.once and args.thread_id else follower.poll(read_owner(runtime/'owner.json')))
        requested = active['thread_id']
        changed = requested != selected
        selected = requested
        if changed:
            meta = None
        now = time.monotonic()
        catalog_error = None
        if selected and (now >= next_meta or changed):
            try:
                with closing(sqlite3.connect((home/'state_5.sqlite').as_uri()+'?mode=ro',uri=True,timeout=0.2)) as con:
                    row = con.execute("SELECT id,COALESCE(NULLIF(name,''),title),rollout_path,model FROM threads WHERE id=?",(selected,)).fetchone()
                meta = dict(id=row[0],title=(row[1] or row[0])[:100],path=row[2],model=row[3]) if row else None
            except (sqlite3.Error, OSError):
                catalog_error = "暂时无法读取当前聊天"
            next_meta = now + 5
        reader = None
        if meta and str(meta['path']).endswith('.jsonl'):
            reader = readers.get(meta['path'])
            if reader is None:
                reader = UsageReader(meta['path'],meta.get('model'))
                readers[meta['path']] = reader
            readers.move_to_end(meta['path'])
            while len(readers)>8:
                readers.popitem(last=False)
        if reader:
            reader.poll()
            state = reader.snapshot()
        else:
            state = {"usage": None, "billing":None,"history_complete":True,
                     "error": "当前页面暂无本地聊天" if not selected else "等待当前聊天的用量记录"}
        state.update({
            "version": 2,
            "thread_id": selected,
            "title": meta["title"] if meta else "当前聊天",
            "heartbeat_ms": int(time.time() * 1000),
            "catalog_error": catalog_error,
            "binding": "automatic",
            "active_window":active,
        })
        atomic_json(runtime / "state.json", state)
        if args.once:
            print(json.dumps({k: v for k, v in state.items() if k != "threads"}, ensure_ascii=True))
            return
        time.sleep(0.5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--thread-id", help="Only used with --once for diagnostics")
    parser.add_argument("--codex-home")
    parser.add_argument("--parent-pid", type=int)
    parser.add_argument("--once", action="store_true")
    run(parser.parse_args())
