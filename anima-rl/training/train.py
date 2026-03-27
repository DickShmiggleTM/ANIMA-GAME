"""
train.py — PPO training entry point for ANIMA Zoi agents.

Usage:
    python -m training.train --stage 0 --timesteps 500000
    python -m training.train --stage 1 --timesteps 1000000 --load models/stage0_final
"""

import argparse
import os
import json
import time
from pathlib import Path

import numpy as np

try:
    from stable_baselines3 import PPO
    from stable_baselines3.common.env_util import make_vec_env
    from stable_baselines3.common.callbacks import (
        CheckpointCallback, EvalCallback, BaseCallback)
    from stable_baselines3.common.monitor import Monitor
    SB3_AVAILABLE = True
except ImportError:
    SB3_AVAILABLE = False
    print("[WARN] stable-baselines3 not installed; training disabled.")
    print("       Install: pip install stable-baselines3[extra]")

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
from envs.anima_env import AnimaEnv


def make_env(stage: int, seed: int = 0):
    def _init():
        env = AnimaEnv(curriculum_stage=stage, seed=seed)
        return Monitor(env)
    return _init


class TelemetryCallback(BaseCallback):
    """Logs episode stats to JSONL for the data pipeline."""

    def __init__(self, log_path: str, verbose: int = 0):
        super().__init__(verbose)
        self.log_path = log_path
        self._file = open(log_path, "a")

    def _on_step(self) -> bool:
        if self.locals.get("dones") is not None:
            for i, done in enumerate(self.locals["dones"]):
                if done and self.locals.get("infos"):
                    info = self.locals["infos"][i]
                    record = {
                        "ts": time.time(),
                        "n_calls": self.n_calls,
                        "episode_reward": info.get("episode", {}).get("r", 0),
                        "episode_length": info.get("episode", {}).get("l", 0),
                        "survived": info.get("survived", False),
                        "final_energy": info.get("energy", 0),
                        "final_hydration": info.get("hydration", 0),
                    }
                    self._file.write(json.dumps(record) + "\n")
                    self._file.flush()
        return True

    def _on_training_end(self):
        self._file.close()


def export_onnx(model, output_path: str, obs_dim: int = 10):
    """Export policy to ONNX with metadata."""
    try:
        import torch
        obs_sample = torch.zeros(1, obs_dim)
        torch.onnx.export(
            model.policy,
            obs_sample,
            output_path,
            input_names=["observation"],
            output_names=["action_logits"],
            opset_version=11,
            dynamic_axes={"observation": {0: "batch_size"},
                          "action_logits": {0: "batch_size"}},
        )
        # Save metadata alongside
        meta = {
            "obs_dim": obs_dim,
            "n_actions": 10,
            "action_names": ["idle", "eat", "drink", "rest", "wander",
                             "socialize", "flee", "build", "share", "call"],
            "obs_schema": ["energy", "hydration", "sleep_toxins", "cortisol",
                           "dopamine", "body_temp_norm", "nearby_count_norm",
                           "food_dist_inv", "water_dist_inv", "time_of_day"],
            "exported_at": time.time(),
        }
        meta_path = output_path.replace(".onnx", "_meta.json")
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=2)
        print(f"[ONNX] Exported to {output_path}")
        print(f"[ONNX] Metadata: {meta_path}")
    except Exception as e:
        print(f"[WARN] ONNX export failed: {e}")


def train(args):
    if not SB3_AVAILABLE:
        print("Cannot train: stable-baselines3 missing.")
        return

    models_dir = Path(args.models_dir)
    logs_dir   = Path(args.logs_dir)
    models_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    print(f"[Train] Curriculum stage {args.stage} | "
          f"{args.timesteps:,} timesteps | {args.n_envs} envs")

    vec_env  = make_vec_env(make_env(args.stage), n_envs=args.n_envs)
    eval_env = make_vec_env(make_env(args.stage, seed=9999), n_envs=1)

    # Load or create model
    if args.load and Path(args.load).exists():
        print(f"[Train] Loading checkpoint: {args.load}")
        model = PPO.load(args.load, env=vec_env)
    else:
        model = PPO(
            policy="MlpPolicy",
            env=vec_env,
            learning_rate=3e-4,
            n_steps=2048,
            batch_size=64,
            n_epochs=10,
            gamma=0.995,
            gae_lambda=0.95,
            clip_range=0.2,
            ent_coef=0.01,
            verbose=1,
            tensorboard_log=str(logs_dir / "tensorboard"),
            policy_kwargs={"net_arch": [128, 128]},
        )

    callbacks = [
        CheckpointCallback(
            save_freq=50_000,
            save_path=str(models_dir / "checkpoints"),
            name_prefix=f"anima_stage{args.stage}",
        ),
        EvalCallback(
            eval_env,
            best_model_save_path=str(models_dir / "best"),
            log_path=str(logs_dir / "eval"),
            eval_freq=25_000,
            deterministic=True,
            render=False,
        ),
        TelemetryCallback(str(logs_dir / f"telemetry_stage{args.stage}.jsonl")),
    ]

    model.learn(
        total_timesteps=args.timesteps,
        callback=callbacks,
        progress_bar=True,
    )

    final_path = str(models_dir / f"stage{args.stage}_final")
    model.save(final_path)
    print(f"[Train] Saved final model: {final_path}")

    onnx_path = str(models_dir / f"stage{args.stage}_policy.onnx")
    export_onnx(model, onnx_path)
    print("[Train] Done.")


def main():
    parser = argparse.ArgumentParser(description="ANIMA Zoi RL Training")
    parser.add_argument("--stage",       type=int,   default=0)
    parser.add_argument("--timesteps",   type=int,   default=500_000)
    parser.add_argument("--n-envs",      type=int,   default=8)
    parser.add_argument("--load",        type=str,   default="")
    parser.add_argument("--models-dir",  type=str,   default="models")
    parser.add_argument("--logs-dir",    type=str,   default="data/logs")
    args = parser.parse_args()
    train(args)


if __name__ == "__main__":
    main()
