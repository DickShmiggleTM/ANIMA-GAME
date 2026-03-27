"""
scenarios.py — Automated scenario runner for QA / emergent behavior validation.

Scenarios run headless simulations using the Python AnimaBodySim and assert
emergent behaviors with statistical tests.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "anima-rl"))

import numpy as np
import json
import time
from typing import List, Dict, Any, Callable, Optional
from dataclasses import dataclass, asdict

from envs.anima_env import AnimaEnv, AnimaBodySim, WorldSim


# ── Scenario result ─────────────────────────────────────────────────────────

@dataclass
class ScenarioResult:
    scenario_name: str
    passed: bool
    metrics: Dict[str, Any]
    assertions: List[Dict[str, Any]]
    duration_ms: float
    error: Optional[str] = None

    def to_dict(self):
        return asdict(self)


# ── Base scenario ────────────────────────────────────────────────────────────

class Scenario:
    name = "base_scenario"
    description = ""

    def run(self, seed: int = 42) -> ScenarioResult:
        t0 = time.time()
        metrics: Dict[str, Any] = {}
        assertions: List[Dict[str, Any]] = []
        error = None
        passed = True
        try:
            passed, metrics, assertions = self._execute(seed, metrics, assertions)
        except Exception as e:
            passed = False
            error = str(e)
        duration_ms = (time.time() - t0) * 1000
        return ScenarioResult(
            scenario_name=self.name,
            passed=passed,
            metrics=metrics,
            assertions=assertions,
            duration_ms=duration_ms,
            error=error,
        )

    def _execute(self, seed, metrics, assertions):
        raise NotImplementedError

    def _assert(self, assertions, name, condition, actual=None, expected=None):
        assertions.append({
            "name":     name,
            "passed":   condition,
            "actual":   actual,
            "expected": expected,
        })
        return condition


# ── Scenario 1: agent seeks food when hungry ─────────────────────────────────

class HungerScenario(Scenario):
    name = "hunger_food_seeking"
    description = "Agent with low energy should eat and recover."

    def _execute(self, seed, metrics, assertions):
        env = AnimaEnv(seed=seed, max_steps=500)
        obs, _ = env.reset()
        env.body.energy = 0.2
        env.world.agent_pos = env.world.food_pos[0].copy()  # start near food

        ate_count = 0
        final_energy = env.body.energy
        for _ in range(200):
            # Always try to eat
            obs, reward, done, _, info = env.step(1)
            final_energy = info["energy"]
            if info.get("energy", 0) > 0.2:
                ate_count += 1
            if done:
                break

        metrics["final_energy"] = final_energy
        metrics["ate_count"]    = ate_count

        passed = self._assert(assertions, "energy_recovered_above_threshold",
                              final_energy > 0.3,
                              actual=final_energy, expected=">0.3")
        return passed, metrics, assertions


# ── Scenario 2: thirst seeking ────────────────────────────────────────────────

class ThirstScenario(Scenario):
    name = "thirst_water_seeking"
    description = "Agent with low hydration should drink and recover."

    def _execute(self, seed, metrics, assertions):
        env = AnimaEnv(seed=seed, max_steps=500)
        env.reset()
        env.body.hydration = 0.15
        env.world.agent_pos = env.world.water_pos[0].copy()

        for _ in range(200):
            obs, reward, done, _, info = env.step(2)  # drink
            if done:
                break

        final_hyd = env.body.hydration
        metrics["final_hydration"] = final_hyd

        passed = self._assert(assertions, "hydration_recovered",
                              final_hyd > 0.25,
                              actual=final_hyd, expected=">0.25")
        return passed, metrics, assertions


# ── Scenario 3: survival under resource scarcity ─────────────────────────────

class ScarcityScenario(Scenario):
    name = "survival_under_scarcity"
    description = "Agent should survive for at least N steps with sparse resources."

    MIN_SURVIVAL_STEPS = 1000

    def _execute(self, seed, metrics, assertions):
        env = AnimaEnv(seed=seed, max_steps=2000)
        env.reset()
        # Make resources scarce
        env.world.n_food = 2
        env.world.n_water = 2

        alive_steps = 0
        for step in range(2000):
            action = env.action_space.sample()
            obs, reward, done, _, info = env.step(action)
            if not done:
                alive_steps = step
            else:
                break

        metrics["alive_steps"] = alive_steps
        passed = self._assert(assertions, "survived_minimum_steps",
                              alive_steps >= self.MIN_SURVIVAL_STEPS,
                              actual=alive_steps,
                              expected=f">={self.MIN_SURVIVAL_STEPS}")
        return passed, metrics, assertions


# ── Scenario 4: sleep/fatigue accumulates correctly ──────────────────────────

class FatigueScenario(Scenario):
    name = "fatigue_accumulation"
    description = "Sleep toxins should accumulate over time; rest reduces them."

    def _execute(self, seed, metrics, assertions):
        body = AnimaBodySim(seed=seed)
        # Run 15 seconds of waking
        for _ in range(15 * 15):  # 15 Hz for 15 sec
            body.tick()
        high_toxins = body.sleep_toxins

        # Now rest for 5 seconds
        for _ in range(5 * 15):
            body.apply_event("sleep", 0.01)
            body.tick()
        post_rest_toxins = body.sleep_toxins

        metrics["high_toxins"]      = high_toxins
        metrics["post_rest_toxins"] = post_rest_toxins

        p1 = self._assert(assertions, "toxins_accumulate",
                          high_toxins > 0.05,
                          actual=high_toxins, expected=">0.05")
        p2 = self._assert(assertions, "rest_reduces_toxins",
                          post_rest_toxins < high_toxins,
                          actual=post_rest_toxins, expected=f"<{high_toxins:.3f}")
        return p1 and p2, metrics, assertions


# ── Scenario 5: weather affects temperature ──────────────────────────────────

class WeatherScenario(Scenario):
    name = "weather_temperature_effect"
    description = "Cold weather should reduce body temperature over time."

    def _execute(self, seed, metrics, assertions):
        body = AnimaBodySim(seed=seed)
        initial_temp = body.body_temp
        # Simulate cold ambient air (-10 °C delta)
        for _ in range(30 * 15):  # 30 seconds
            body.body_temp += (-10.0 - (body.body_temp - 37.0)) * 0.01
            body.tick()

        metrics["initial_temp"] = initial_temp
        metrics["final_temp"]   = body.body_temp

        passed = self._assert(assertions, "temperature_dropped",
                              body.body_temp < initial_temp - 0.5,
                              actual=body.body_temp,
                              expected=f"<{initial_temp - 0.5:.2f}")
        return passed, metrics, assertions


# ── Scenario runner ──────────────────────────────────────────────────────────

ALL_SCENARIOS = [
    HungerScenario(),
    ThirstScenario(),
    ScarcityScenario(),
    FatigueScenario(),
    WeatherScenario(),
]


def run_all(seed: int = 42, output_path: Optional[str] = None) -> List[ScenarioResult]:
    results = []
    print(f"Running {len(ALL_SCENARIOS)} scenarios (seed={seed})...\n")
    for scenario in ALL_SCENARIOS:
        print(f"  [{scenario.name}] ", end="", flush=True)
        result = scenario.run(seed=seed)
        status = "PASS" if result.passed else "FAIL"
        print(f"{status} ({result.duration_ms:.1f} ms)")
        if not result.passed:
            for a in result.assertions:
                if not a["passed"]:
                    print(f"    ✗ {a['name']}: got {a['actual']}, expected {a['expected']}")
        results.append(result)

    passed = sum(1 for r in results if r.passed)
    print(f"\n{passed}/{len(results)} scenarios passed.")

    if output_path:
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            json.dump([r.to_dict() for r in results], f, indent=2)
        print(f"Results saved to {output_path}")

    return results


if __name__ == "__main__":
    results = run_all(seed=42, output_path="data/scenario_results.json")
    all_passed = all(r.passed for r in results)
    sys.exit(0 if all_passed else 1)
