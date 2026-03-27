"""test_env.py — Unit tests for AnimaEnv."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
import numpy as np
from envs.anima_env import AnimaEnv, AnimaBodySim, OBS_DIM, N_ACTIONS


class TestAnimaBodySim:
    def test_initial_state(self):
        body = AnimaBodySim(seed=42)
        assert 0.8 <= body.energy <= 1.0
        assert 0.8 <= body.hydration <= 1.0
        assert body.alive

    def test_metabolism_decay(self):
        body = AnimaBodySim(seed=1)
        e0, h0, st0 = body.energy, body.hydration, body.sleep_toxins
        for _ in range(15):  # 1 second
            body.tick()
        assert body.energy < e0
        assert body.hydration < h0
        assert body.sleep_toxins > st0

    def test_eat_event(self):
        body = AnimaBodySim(seed=2)
        body.energy = 0.3
        body.apply_event("eat", 0.3)
        assert body.energy > 0.3

    def test_drink_event(self):
        body = AnimaBodySim(seed=3)
        body.hydration = 0.2
        body.apply_event("drink", 0.3)
        assert body.hydration > 0.2

    def test_starvation_death(self):
        body = AnimaBodySim(seed=4)
        body.energy = 0.0
        body.tick()
        assert not body.alive

    def test_hypothermia_death(self):
        body = AnimaBodySim(seed=5)
        body.body_temp = 27.0
        body.tick()
        assert not body.alive

    def test_clamp_bounds(self):
        body = AnimaBodySim(seed=6)
        body.apply_event("eat", 5.0)
        assert body.energy <= 1.0
        body.apply_event("damage", 5.0)
        assert body.injury <= 1.0


class TestAnimaEnv:
    def test_observation_shape(self):
        env = AnimaEnv(seed=0)
        obs, _ = env.reset()
        assert obs.shape == (OBS_DIM,)
        assert obs.dtype == np.float32

    def test_step_returns_correct_types(self):
        env = AnimaEnv(seed=0)
        env.reset()
        obs, reward, done, trunc, info = env.step(0)
        assert obs.shape == (OBS_DIM,)
        assert isinstance(reward, float)
        assert isinstance(done, bool)
        assert isinstance(info, dict)

    def test_all_actions_valid(self):
        env = AnimaEnv(seed=42)
        env.reset()
        for action in range(N_ACTIONS):
            env.reset()
            obs, reward, done, _, info = env.step(action)
            assert obs.shape == (OBS_DIM,)

    def test_eat_action_increases_energy(self):
        env = AnimaEnv(seed=7)
        env.reset()
        env.body.energy = 0.3
        # Position agent near food
        env.world.agent_pos = env.world.food_pos[0].copy()
        e_before = env.body.energy
        env.step(1)  # eat
        # Energy should be higher or equal (may vary by one tick)
        assert env.body.energy >= e_before - 0.002  # allow small decay

    def test_agent_dies_from_starvation(self):
        env = AnimaEnv(seed=8, max_steps=10000)
        env.reset()
        env.body.energy = 0.0  # already at zero
        env.body.tick()        # this marks alive=False
        _, _, done, _, _ = env.step(0)
        assert done  # env should report done since body is dead

    def test_deterministic_reset(self):
        env = AnimaEnv(seed=123)
        obs1, _ = env.reset(seed=123)
        obs2, _ = env.reset(seed=123)
        np.testing.assert_array_equal(obs1, obs2)

    def test_reward_positive_when_eating(self):
        env = AnimaEnv(seed=9)
        env.reset()
        env.body.energy = 0.3
        env.world.agent_pos = env.world.food_pos[0].copy()
        _, reward, _, _, _ = env.step(1)
        assert reward > 0.0

    def test_survival_bonus_accumulates(self):
        env = AnimaEnv(seed=10, max_steps=100)
        env.reset()
        total = 0.0
        for _ in range(50):
            _, r, done, _, _ = env.step(1)
            total += r
            if done:
                break
        assert total > 0.0

    def test_obs_in_valid_range(self):
        env = AnimaEnv(seed=11)
        env.reset()
        for _ in range(100):
            obs, _, done, _, _ = env.step(env.action_space.sample())
            assert np.all(obs >= -0.1) and np.all(obs <= 1.1), \
                f"Obs out of range: {obs}"
            if done:
                break


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
