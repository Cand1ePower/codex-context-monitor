"""Read the current Codex window route from its existing desktop logs.

Only window IDs, route IDs and timestamps are retained. New/unsupported pages
clear the selection. Never select the most recently *active backend* thread.
"""
import datetime as dt
import json
import os
from pathlib import Path
import re
import time

ROUTE = re.compile(r'ownerRoutePath=(\S+) windowId=(\d+)')
FOCUS = re.compile(r'rendererWindowAppearance=primary rendererWindowFocused=true rendererWindowId=(\d+)')
LOCAL = re.compile(r'^/local/([a-f0-9-]{36})(?:[/?#]|$)')


class ActiveChat:
    def __init__(self, log_root=None):
        self.root = Path(log_root or Path(os.environ.get('LOCALAPPDATA',''))/'Codex/Logs')
        self.pid = None
        self.files = {}
        self.routes = {}
        self.focused = None
        self.focus_time = ''
        self.next_scan = 0

    def consume(self, line):
        timestamp = line[:24]
        if 'IAB_LIFECYCLE received browser sidebar owner sync ' in line:
            match = ROUTE.search(line)
            if match:
                route, wid = match.groups()
                if timestamp >= self.routes.get(wid, ('',None))[0]:
                    self.routes[wid] = (timestamp, route)
        if 'rendererWindowFocused=true' in line:
            match = FOCUS.search(line)
            if match and timestamp >= self.focus_time:
                self.focus_time, self.focused = timestamp, match.group(1)

    def selection(self):
        wid = self.focused if self.focused in self.routes else (next(iter(self.routes)) if len(self.routes) == 1 else None)
        route = self.routes.get(wid, ('',None))[1]
        match = LOCAL.match(route or '')
        return {'thread_id':match.group(1) if match else None, 'window_id':wid,
                'route':route, 'process_id':self.pid, 'source':'active_window_log',
                'status':'following' if match else ('new_or_unsupported_page' if route is not None else 'waiting_for_window')}

    def poll(self, pid):
        if pid != self.pid:
            self.pid = pid
            self.files.clear(); self.routes.clear(); self.focused = None; self.focus_time = ''; self.next_scan = 0
        if not pid:
            return self.selection()
        now = time.monotonic()
        if now >= self.next_scan:
            candidates = []
            try:
                for path in self.root.glob(f'*/*/*/*-{pid}-t0-*.log'):
                    try:
                        stat = path.stat()
                    except OSError:
                        continue  # A log can rotate between glob() and stat().
                    candidates.append((stat.st_mtime, path, stat.st_size))
            except OSError:
                pass
            candidates = sorted(candidates, key=lambda item:item[0])[-4:]
            for _, path, size in candidates:
                if path not in self.files:
                    self.files[path] = {'offset':max(0,size-8*1024*1024), 'partial':b'', 'new':True}
            paths = {item[1] for item in candidates}
            self.files = {p:v for p,v in self.files.items() if p in paths}
            self.next_scan = now + 2
        for path, state in self.files.items():
            try:
                if path.stat().st_size < state['offset']:
                    state.update(offset=0,partial=b'',new=True)
                with path.open('rb') as stream:
                    stream.seek(state['offset'])
                    if state['new'] and state['offset']:
                        stream.readline()
                    state['new'] = False
                    data = stream.read(8*1024*1024)
                    state['offset'] = stream.tell()
                lines = (state['partial']+data).split(b'\n');state['partial'] = lines.pop()
                for line in lines:
                    if b'ownerRoutePath=' in line or b'rendererWindowFocused=true' in line:
                        self.consume(line.decode('utf-8', errors='replace'))
            except OSError:
                continue
        return self.selection()


def read_owner(path):
    try:
        data = json.loads(Path(path).read_text(encoding='utf-8-sig'))
        if time.time()*1000-data.get('heartbeat_ms',0) > 6000:
            return None
        value = data.get('process_id')
        return value if type(value) is int and value > 0 else None
    except (OSError, ValueError, TypeError):
        return None
