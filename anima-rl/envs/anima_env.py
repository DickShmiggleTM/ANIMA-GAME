"""
anima_env.py — Gymnasium environment mirroring the C++ Body simulation.

Observation vector (OBS_DIM = 10):
    [energy, hydration, sleep_toxins, cortisol, dopamine,
     body_temp_norm, nearby_count_norm, food_dist_inv, water_dist_inv, time_of_day]

Action space (discrete, 10 actions):
    0=idle, 1=eat, 2=drink, 3=rest, 4=wander,
    5=socialize, 6=flee, 7=build, 8=share, 9=call
"""

import numpy as np
import gymnasium as gym
from gymnasium import spaces
from typing import Dict, Any, Tuple, Optional

OBS_DIM = 10
N_ACTIONS = 10

ACTIONS = ["idle", "eat", "drink", "rest", "wander",
           "socialize", "flee", "build", "share", "call"]

# Reward weights (homeostasis + social)
RW_ENERGY     = 1.5
RW_HYDRATION  = 1.5
RW_SLEEP      = 0.5
RW_SOCIAL     = 0.3
RW_SURVIVE    = 5.0  # bonus for staying alive per step
RW_DEATH      = -20.0


class AnimaBodySim:
    """Lightweight Python replica of the C++ Body simulation."""

    TICK_RATE = 15.0  # Hz

    def __init__(self, seed: int = 0):
        self.rng = np.random.default_rng(seed)
        self.reset()

    def reset(self):
        self.energy        = 0.8 + self.rng.uniform(0, 0.2)
        self.hydration     = 0.8 + self.rng.uniform(0, 0.2)
        self.sleep_toxins  = self.rng.uniform(0, 0.1)
        self.cortisol      = 0.05
        self.dopamine      = 0.5
        self.endorphin     = 0.3
        self.body_temp     = 37.0
        self.injury        = 0.0
        self.age_ticks     = 0
        self.alive         = True

    def tick(self, dt: float = 1.0 / 15.0):
        mr = 1.0 - self.sleep_toxins * 0.3
        self.energy       -= 0.0004 * mr * dt * self.TICK_RATE
        self.hydration    -= 0.0005 * mr * dt * self.TICK_RATE
        self.sleep_toxins += 0.0003 * dt * self.TICK_RATE
        self._update_hormones(dt)
        self.age_ticks    += 1
        self._clamp()
        self._check_alive()

    def apply_event(self, event: str, amount: float = 0.2):
        if event == "eat":
            self.energy    = min(1.0, self.energy + amount)
            self.dopamine  = min(1.0, self.dopamine + 0.05)
        elif event == "drink":
            self.hydration = min(1.0, self.hydration + amount)
        elif event == "sleep":
            self.sleep_toxins = max(0.0, self.sleep_toxins - amount)
            self.cortisol     *= 0.95
        elif event == "damage":
            self.injury    = min(1.0, self.injury + amount)
            self.energy    = max(0.0, self.energy - amount * 0.3)
            self.cortisol  = min(1.0, self.cortisol + 0.15)
        elif event == "social_positive":
            self.dopamine  = min(1.0, self.dopamine + 0.05)
            self.cortisol  = max(0.0, self.cortisol - 0.02)

    def _update_hormones(self, dt: float):
        stress = (1 - self.energy) * 0.3 + (1 - self.hydration) * 0.3 + \
                 self.sleep_toxins * 0.2 + self.injury * 0.2
        stress = float(np.clip(stress, 0, 1))
        lr = 0.05 * dt * self.TICK_RATE
        self.cortisol  += (stress - self.cortisol) * lr
        self.dopamine  += ((1 - self.cortisol * 0.5) - self.dopamine) * (lr * 0.4)

    def _clamp(self):
        self.energy       = float(np.clip(self.energy,       0, 1))
        self.hydration    = float(np.clip(self.hydration,    0, 1))
        self.sleep_toxins = float(np.clip(self.sleep_toxins, 0, 1))
        self.cortisol     = float(np.clip(self.cortisol,     0, 1))
        self.dopamine     = float(np.clip(self.dopamine,     0, 1))
        self.endorphin    = float(np.clip(self.endorphin,    0, 1))
        self.body_temp    = float(np.clip(self.body_temp,    28, 43))

    def _check_alive(self):
        if self.energy <= 0 or self.hydration <= 0 or \
           self.body_temp < 29 or self.body_temp > 42:
            self.alive = False

    def get_obs_partial(self) -> np.ndarray:
        """Returns body-only portion of obs; env fills spatial slots."""
        return np.array([
            self.energy,
            self.hydration,
            self.sleep_toxins,
            self.cortisol,
            self.dopamine,
            (self.body_temp - 30.0) / 20.0,
        ], dtype=np.float32)


class WorldSim:
    """Minimal world: food and water nodes on a 2D plane."""

    def __init__(self, seed: int = 0, size: float = 20.0,
                 n_food: int = 4, n_water: int = 4):
        self.rng    = np.random.default_rng(seed)
        self.size   = size
        self.n_food = n_food
        self.n_water = n_water
        self.reset()

    def reset(self):
        self.agent_pos  = np.zeros(2, dtype=np.float32)
        self.food_pos   = self.rng.uniform(-self.size/2, self.size/2,
                                           (self.n_food, 2)).astype(np.float32)
        self.water_pos  = self.rng.uniform(-self.size/2, self.size/2,
                                           (self.n_water, 2)).astype(np.float32)
        self.food_avail  = np.ones(self.n_food,  dtype=bool)
        self.water_avail = np.ones(self.n_water, dtype=bool)
        self.time_of_day = 0.0  # 0..24

    def step(self, action: int, dt: float = 1.0 / 15.0) -> Tuple[str, bool, bool]:
        """Returns (event, food_consumed, water_consumed)."""
        move_speed = 3.0  # units/s
        event = "idle"
        ate = False
        drank = False

        # Move toward nearest valid target based on action
        if action == 1 and self.food_avail.any():   # eat
            idx = self._nearest(self.food_pos, self.food_avail)
            self._move_toward(self.food_pos[idx], move_speed * dt)
            if np.linalg.norm(self.agent_pos - self.food_pos[idx]) < 1.0:
                self.food_avail[idx] = False
                event = "eat"
                ate = True

        elif action == 2 and self.water_avail.any():  # drink
            idx = self._nearest(self.water_pos, self.water_avail)
            self._move_toward(self.water_pos[idx], move_speed * dt)
            if np.linalg.norm(self.agent_pos - self.water_pos[idx]) < 1.0:
                self.water_avail[idx] = False
                event = "drink"
                drank = True

        elif action == 3:  # rest
            event = "sleep"

        elif action == 4:  # wander
            # Random walk
            direction = self.rng.standard_normal(2).astype(np.float32)
            norm = np.linalg.norm(direction) + 1e-8
            self.agent_pos += (direction / norm) * move_speed * 0.3 * dt
            self.agent_pos = np.clip(self.agent_pos, -self.size/2, self.size/2)

        # Regenerate depleted resources occasionally
        if self.rng.random() < 0.002:
            self.food_avail[:] = True
        if self.rng.random() < 0.002:
            self.water_avail[:] = True

        # Day cycle
        self.time_of_day = (self.time_of_day + dt * 24.0 / 120.0) % 24.0

        return event, ate, drank

    def get_spatial_obs(self) -> np.ndarray:
        """4 spatial features: nearby_count_norm, food_dist_inv, water_dist_inv, tod"""
        nearby = 0.1  # placeholder (no multi-agent in solo env)
        food_d  = self._min_dist(self.food_pos,  self.food_avail)
        water_d = self._min_dist(self.water_pos, self.water_avail)
        food_inv  = float(np.clip(1.0 - food_d  / (self.size * 0.7), 0, 1))
        water_inv = float(np.clip(1.0 - water_d / (self.size * 0.7), 0, 1))
        tod_norm  = self.time_of_day / 24.0
        return np.array([nearby, food_inv, water_inv, tod_norm], dtype=np.float32)

    def _nearest(self, positions: np.ndarray, avail: np.ndarray) -> int:
        dists = np.linalg.norm(positions - self.agent_pos, axis=1)
        dists[~avail] = 1e9
        return int(np.argmin(dists))

    def _min_dist(self, positions: np.ndarray, avail: np.ndarray) -> float:
        if not avail.any():
            return 999.0
        dists = np.linalg.norm(positions[avail] - self.agent_pos, axis=1)
        return float(np.min(dists))

    def _move_toward(self, target: np.ndarray, speed: float):
        diff = target - self.agent_pos
        dist = np.linalg.norm(diff) + 1e-8
        self.agent_pos += (diff / dist) * min(speed, dist)
        self.agent_pos = np.clip(self.agent_pos, -self.size/2, self.size/2)


class AnimaEnv(gym.Env):
    """
    Single-agent ANIMA environment for RL training.

    Curriculum stages:
        0 — survival basics (hunger + thirst only)
        1 — add sleep/fatigue
        2 — add social interactions (multi-agent, future)
        3 — full biochemistry + predators
    """

    metadata = {"render_modes": ["human", "ansi"], "render_fps": 15}

    def __init__(self, curriculum_stage: int = 0,
                 max_steps: int = 3000, seed: int = 0):
        super().__init__()
        self.curriculum_stage = curriculum_stage
        self.max_steps = max_steps
        self._seed = seed

        self.observation_space = spaces.Box(
            low=0.0, high=1.0, shape=(OBS_DIM,), dtype=np.float32)
        self.action_space = spaces.Discrete(N_ACTIONS)

        self.body = AnimaBodySim(seed=seed)
        self.world = WorldSim(seed=seed)
        self._step_count = 0

    def reset(self, *, seed: Optional[int] = None,
              options: Optional[Dict] = None) -> Tuple[np.ndarray, Dict]:
        if seed is not None:
            self._seed = seed
        self.body  = AnimaBodySim(seed=self._seed)
        self.world = WorldSim(seed=self._seed)
        self._step_count = 0
        return self._get_obs(), {}

    def step(self, action: int) -> Tuple[np.ndarray, float, bool, bool, Dict]:
        dt = 1.0 / AnimaBodySim.TICK_RATE
        event, ate, drank = self.world.step(action, dt)
        if event != "idle":
            self.body.apply_event(event, amount=0.25)
        self.body.tick(dt)
        self._step_count += 1

        obs    = self._get_obs()
        reward = self._compute_reward(ate, drank)
        dead   = not self.body.alive
        done   = dead or self._step_count >= self.max_steps
        info   = {
            "energy":       self.body.energy,
            "hydration":    self.body.hydration,
            "sleep_toxins": self.body.sleep_toxins,
            "cortisol":     self.body.cortisol,
            "dopamine":     self.body.dopamine,
            "survived":     not dead,
        }
        return obs, reward, done, False, info

    def _get_obs(self) -> np.ndarray:
        body_obs    = self.body.get_obs_partial()
        spatial_obs = self.world.get_spatial_obs()
        return np.concatenate([body_obs, spatial_obs]).astype(np.float32)

    def _compute_reward(self, ate: bool, drank: bool) -> float:
        # Survival bonus
        r = RW_SURVIVE / self.max_steps if self.body.alive else RW_DEATH

        # Homeostasis shaping: reward staying in healthy range
        r += RW_ENERGY    * (self.body.energy    - 0.5)   * 0.1
        r += RW_HYDRATION * (self.body.hydration - 0.5)   * 0.1
        r += RW_SLEEP     * (0.5 - self.body.sleep_toxins) * 0.05

        # Explicit consumption rewards
        if ate:   r += 1.0
        if drank: r += 1.0

        # Stage 1+: penalize high cortisol
        if self.curriculum_stage >= 1:
            r -= 0.1 * self.body.cortisol

        return float(r)

    def render(self) -> Optional[str]:
        if self.render_mode == "ansi":
            return (f"Step {self._step_count:4d} | "
                    f"E:{self.body.energy:.2f} H:{self.body.hydration:.2f} "
                    f"ST:{self.body.sleep_toxins:.2f} "
                    f"Cort:{self.body.cortisol:.2f} Dopa:{self.body.dopamine:.2f}")
        return None
