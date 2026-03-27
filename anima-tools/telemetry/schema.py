"""
schema.py — Canonical event schema for ANIMA telemetry.

All events written to .jsonl logs follow this schema.
Used by both the Godot Telemetry autoload and the Python data pipeline.
"""

from dataclasses import dataclass, asdict, field
from typing import List, Optional, Dict, Any
import time
import json


# ── Base event ──────────────────────────────────────────────────────────────

@dataclass
class BaseEvent:
    type: str
    t: int        # simulation tick
    ts: float     # unix timestamp
    session: str  # session id

    def to_json(self) -> str:
        return json.dumps(asdict(self))


# ── Lifecycle ────────────────────────────────────────────────────────────────

@dataclass
class BirthEvent(BaseEvent):
    type: str = "birth"
    zoi_id: int = 0
    parent_ids: List[int] = field(default_factory=list)
    genetics: Dict[str, Any] = field(default_factory=dict)


@dataclass
class DeathEvent(BaseEvent):
    type: str = "death"
    zoi_id: int = 0
    cause: str = ""           # starvation, dehydration, hypothermia, predator, old_age
    age_ticks: int = 0
    final_energy: float = 0.0
    final_hydration: float = 0.0


# ── Biochemistry ─────────────────────────────────────────────────────────────

@dataclass
class ObsActionEvent(BaseEvent):
    type: str = "obs_action"
    zoi_id: int = 0
    obs: List[float] = field(default_factory=list)
    action: int = 0
    reward: float = 0.0


@dataclass
class ResourceConsumedEvent(BaseEvent):
    type: str = "resource_consumed"
    zoi_id: int = 0
    resource_type: str = ""
    amount: float = 0.0
    energy_before: float = 0.0
    energy_after: float = 0.0


# ── Social ───────────────────────────────────────────────────────────────────

@dataclass
class InteractionEvent(BaseEvent):
    type: str = "interaction"
    actor_id: int = 0
    target_id: int = 0
    interaction_type: str = ""   # share, attack, groom, mate, teach
    trust_delta: float = 0.0
    outcome: str = ""


@dataclass
class LanguageTokenEvent(BaseEvent):
    type: str = "language_token"
    emitter_id: int = 0
    token: int = 0
    context: str = ""
    listeners: List[int] = field(default_factory=list)


# ── World ────────────────────────────────────────────────────────────────────

@dataclass
class WeatherEvent(BaseEvent):
    type: str = "weather_change"
    weather: str = ""
    intensity: float = 0.0
    affected_zoi: int = 0


@dataclass
class PredatorAttackEvent(BaseEvent):
    type: str = "predator_attack"
    predator_id: int = 0
    target_id: int = 0
    damage: float = 0.0
    target_fled: bool = False


@dataclass
class StructureBuildEvent(BaseEvent):
    type: str = "structure_built"
    builder_id: int = 0
    structure_type: str = ""
    location: Dict[str, float] = field(default_factory=dict)


# ── Registry of known event types ───────────────────────────────────────────

EVENT_TYPES = {
    "birth":             BirthEvent,
    "death":             DeathEvent,
    "obs_action":        ObsActionEvent,
    "resource_consumed": ResourceConsumedEvent,
    "interaction":       InteractionEvent,
    "language_token":    LanguageTokenEvent,
    "weather_change":    WeatherEvent,
    "predator_attack":   PredatorAttackEvent,
    "structure_built":   StructureBuildEvent,
}


def make_event(type_name: str, tick: int, session: str, **kwargs) -> BaseEvent:
    cls = EVENT_TYPES.get(type_name, BaseEvent)
    return cls(type=type_name, t=tick, ts=time.time(), session=session, **kwargs)
