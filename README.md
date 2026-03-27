# ANIMA-GAME

ANIMA is a modern, AI-first spiritual successor to **Creatures (1996)**.

The game centers on autonomous NPCs called **Zoi** (small hobgoblin/hobbit-like creatures, up to ~3 ft tall) who learn continuously from:

- Their own lived experiences.
- Social interaction with other Zoi.
- Inter-generational transfer (offspring inheriting tendencies and learned priors).

The long-term vision blends:

- **ALife simulation** (biochemistry, needs, emotion, memory).
- **Emergent civilization behaviors** (relationships, mimicry, proto-culture, language signals).
- **Light strategy / tower-defense pressure** through ecology, seasons, and predators.

---

## Core Design Pillars

1. **Embodied Intelligence**
   - Every Zoi has a physical/chemical state that drives behavior.
   - "Emotions" are derived from biochemical patterns, not hard-coded mood labels.

2. **Learning Over Scripting**
   - Baseline behaviors are trained with RL/imitation.
   - Runtime decisions are inference-driven and context-sensitive.

3. **Emergence Over Direct Control**
   - The player influences environment constraints and opportunities.
   - Society-level behavior emerges from many local agent interactions.

4. **Scalable Simulation**
   - Keep heavy simulation out of Godot's scene tree.
   - Use data-oriented architecture and clear boundaries between body/mind/visual shell.

---

## Godot ALife Architecture (Body / Mind / Shell)

### 1) Body — C++ GDExtension (Data-Oriented Simulation)

A custom ECS-like simulation layer runs independently from Godot nodes.

**Responsibilities:**
- Per-agent biochemical state updates at fixed ticks.
- Homeostasis variables (examples):
  - blood sugar / energy reserve
  - hydration
  - fatigue and sleep toxins
  - stress hormones (e.g., cortisol)
  - reward chemistry proxies (e.g., dopamine/endorphin signals)
- Environmental coupling (temperature, toxins, injury, disease).
- Efficient batch updates for hundreds of agents.

**Why C++:**
- Deterministic, cache-friendly updates.
- Lower CPU and battery load than node-heavy per-agent logic.

### 2) Mind — Godot RL Agents + ONNX Inference

Behavior policy training happens offline (Python), then deployed in-game.

**Training stack (offline):**
- PyTorch / Stable Baselines3 / custom curriculum loops.
- Multi-objective rewards tied to biochemical homeostasis + social outcomes.

**Runtime stack (in Godot):**
- ONNX policies loaded for local inference.
- Policy inputs include body state, nearby context, memory-derived summaries, and social signals.
- Policy outputs are high-level intents (eat/drink/rest/flee/build/share/call/etc.).

### 3) Shell — GDScript + Godot Nodes (Visual Puppet Layer)

Godot scene instances represent visuals, animation, and player readability.

**Responsibilities:**
- Read body simulation state snapshots.
- Read brain intent outputs.
- Execute movement/animation/state machine transitions.
- Display VFX/UI debug overlays (thoughts, needs, relationship hints).

**Design rule:** keep shell "dumb" and deterministic; all intelligence lives in Body + Mind systems.

---

## Physiological & Psychological Simulation

### Survival Homeostasis

- **Food/Water:** explicit energy and hydration reservoirs.
- **Temperature:** biome/weather impacts body heat and performance.
- **Sleep:** wake-time accumulates fatigue toxins, reducing sensory fidelity and action quality.

### Emotion as Biochemistry

Treat emotions as emergent labels over chemistry + context:

- High cortisol + low health + nearby threat ⇒ **fear** tendencies (flee/hide/group up).
- Adequate energy + high endorphin + trusted ally proximity ⇒ **safety/affection** tendencies (social grooming, sharing, bonding).

### Habit Formation via Episodic Reinforcement

- Maintain episodic memory of need → action → outcome.
- Repeated successful pathways gain strength (habit bias).
- Example: repeated success with purple berries for hunger creates food preference under pressure.

---

## Social Dynamics & Emergent Society

### Relationship Memory Graphs

Each Zoi maintains a local weighted social graph:

- Positive interactions increase trust weight.
- Harmful interactions decrease trust weight.

These weights bias:
- proximity preferences,
- collaboration likelihood,
- mating choices,
- conflict/avoidance behavior.

### Culture via Mimicry

- Younger/lower-status Zoi can copy successful behaviors from visible peers.
- Local clusters converge on techniques (e.g., shared building routines), creating micro-cultures.

### Proto-Language Signals

- Agents emit symbolic vocal tokens linked to objects/events.
- Shared repetition grounds local meaning over time.
- Different groups can diverge into localized dialects.

---

## Strategy Loop: Ecological Pressure Instead of Scripted Waves

Rather than fixed enemy waves, use a living pressure system:

- Night predators.
- Seasonal scarcity.
- Weather hazards.
- Competing fauna.

This pressure forces adaptive social behavior:

- clustering,
- fire use,
- palisade/shelter construction,
- lookout assignment,
- resource storage.

### Player Role: Guiding Spirit

The player does not micromanage citizens directly. They shape outcomes by environmental intervention:

- place resources,
- alter weather,
- influence terrain,
- reward/punish individuals to nudge policy learning.

---

## Phased Development Plan

### Phase 1 (Months 1–3): Internal Engine

- Build C++ GDExtension biochemical simulation core.
- Integrate Godot RL Agents training/inference pipeline.
- **Milestone:** one agent (cube proxy) maintains hydration/energy by seeking water/food objects from internal needs.

### Phase 2 (Months 4–6): Memory & Social Dynamics

- Implement per-agent relationship memory graph.
- Add mimicry/imitation mechanisms.
- **Milestone:** small tribe forms stable preferences (affiliate with helpers, avoid aggressors).

### Phase 3 (Months 7–9): Environmental Pressures

- Add day/night, weather, seasons, flora/fauna loops.
- Introduce discoverable crafting combinations.
- **Milestone:** tribe survives harsh periods via emergent shelter/fire/tool behaviors.

### Phase 4 (Months 10–12): Player Tools, UX, Mobile Optimization

- Build citizen scan/inspection UI for thoughts, chemistry, and social ties.
- Add player intervention tools (terrain/resource/environment nudges).
- Optimize for Android (profiling, UI scaling, touch workflows).

---

## Technical Priorities & Non-Goals (Early)

### Priorities

- Deterministic simulation tick pipeline.
- Data recording for training + debugging.
- Fast iteration loop between offline training and in-engine inference.
- Observability tools for understanding emergent outcomes.

### Non-Goals (initial prototypes)

- Large visual fidelity.
- Massive world size.
- Complex narrative systems.

First prove that **learning + chemistry + social memory** generate believable emergent behavior.

---

## Immediate Next Steps

1. Define a minimal `AgentState` schema (body, sensor, memory summary, action intent).
2. Implement fixed-timestep simulation loop in GDExtension.
3. Stand up a toy RL environment with only thirst/hunger and two resource types.
4. Export first ONNX policy and validate deterministic runtime inference in Godot.
5. Add debug HUD for per-agent needs and chosen intents.

