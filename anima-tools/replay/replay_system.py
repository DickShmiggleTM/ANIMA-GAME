"""
replay_system.py — Deterministic replay: seed + event log → reproduce scenario.

Records:
    - Initial RNG seed
    - All world events (resource spawns, weather changes, predator spawns)
    - All agent actions and body state snapshots at keyframes

Replay:
    - Restore seed → regenerate same initial conditions
    - Re-apply recorded events in order → deterministic reproduction
"""

import json
import gzip
import time
from dataclasses import dataclass, asdict, field
from typing import List, Dict, Any, Optional, Iterator
from pathlib import Path


@dataclass
class ReplayHeader:
    version: str = "1.0"
    session_id: str = ""
    seed: int = 0
    start_ts: float = 0.0
    end_ts: float = 0.0
    total_ticks: int = 0
    zoi_count: int = 0


@dataclass
class ReplayEvent:
    tick: int
    ts: float
    type: str
    data: Dict[str, Any] = field(default_factory=dict)


class ReplayRecorder:
    """Records a session for later deterministic replay."""

    def __init__(self, session_id: str, seed: int):
        self._header = ReplayHeader(
            session_id=session_id,
            seed=seed,
            start_ts=time.time(),
        )
        self._events: List[ReplayEvent] = []

    def record(self, tick: int, event_type: str, data: Dict[str, Any] = None):
        self._events.append(ReplayEvent(
            tick=tick,
            ts=time.time(),
            type=event_type,
            data=data or {},
        ))

    def record_keyframe(self, tick: int, entity_states: List[Dict]):
        """Full state snapshot for seek/scrub support."""
        self.record(tick, "keyframe", {"states": entity_states})

    def save(self, path: str, compress: bool = True):
        self._header.end_ts = time.time()
        self._header.total_ticks = self._events[-1].tick if self._events else 0
        payload = {
            "header": asdict(self._header),
            "events": [asdict(e) for e in self._events],
        }
        data = json.dumps(payload, separators=(",", ":")).encode()
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        if compress:
            with gzip.open(path, "wb") as f:
                f.write(data)
        else:
            with open(path, "wb") as f:
                f.write(data)
        print(f"[Replay] Saved {len(self._events)} events to {path}")

    @classmethod
    def load(cls, path: str) -> "ReplayReader":
        return ReplayReader(path)


class ReplayReader:
    """Reads a replay file and streams events."""

    def __init__(self, path: str):
        self._path = path
        if path.endswith(".gz"):
            with gzip.open(path, "rb") as f:
                payload = json.loads(f.read())
        else:
            with open(path) as f:
                payload = json.load(f)
        self.header = ReplayHeader(**payload["header"])
        self._events = [ReplayEvent(**e) for e in payload["events"]]

    def events(self) -> Iterator[ReplayEvent]:
        yield from self._events

    def events_at_tick(self, tick: int) -> List[ReplayEvent]:
        return [e for e in self._events if e.tick == tick]

    def keyframes(self) -> Iterator[ReplayEvent]:
        for e in self._events:
            if e.type == "keyframe":
                yield e

    def nearest_keyframe(self, tick: int) -> Optional[ReplayEvent]:
        best = None
        for kf in self.keyframes():
            if kf.tick <= tick:
                best = kf
        return best

    def summary(self) -> Dict:
        counts: Dict[str, int] = {}
        for e in self._events:
            counts[e.type] = counts.get(e.type, 0) + 1
        return {
            "session_id":   self.header.session_id,
            "seed":         self.header.seed,
            "total_ticks":  self.header.total_ticks,
            "event_counts": counts,
        }
