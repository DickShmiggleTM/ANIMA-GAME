#pragma once
/**
 * ecs_types.h — Internal ECS component arrays (Structure of Arrays).
 * Not part of the public API; included by ECS systems only.
 */
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* Maximum entities supported without reallocation. */
#define ANIMA_MAX_ENTITIES 1024

/* ── Component arrays (SoA layout for cache efficiency) ─────────────────── */

typedef struct CoreVitals {
    float energy       [ANIMA_MAX_ENTITIES];
    float hydration    [ANIMA_MAX_ENTITIES];
    float sleep_toxins [ANIMA_MAX_ENTITIES];
    float injury       [ANIMA_MAX_ENTITIES];
} CoreVitals;

typedef struct Metabolism {
    float energy_decay_rate    [ANIMA_MAX_ENTITIES];  /* per tick */
    float hydration_decay_rate [ANIMA_MAX_ENTITIES];
    float metabolic_rate       [ANIMA_MAX_ENTITIES];  /* multiplier */
} Metabolism;

typedef struct Hormones {
    float cortisol   [ANIMA_MAX_ENTITIES];
    float dopamine   [ANIMA_MAX_ENTITIES];
    float endorphin  [ANIMA_MAX_ENTITIES];
    float adrenaline [ANIMA_MAX_ENTITIES];
} Hormones;

typedef struct Thermoregulation {
    float body_temp         [ANIMA_MAX_ENTITIES];  /* °C */
    float ambient_temp      [ANIMA_MAX_ENTITIES];  /* °C set by environment */
    float insulation        [ANIMA_MAX_ENTITIES];  /* 0..1 */
} Thermoregulation;

typedef struct Reproduction {
    float fertility         [ANIMA_MAX_ENTITIES];  /* 0..1 */
    uint32_t mating_cooldown[ANIMA_MAX_ENTITIES];  /* ticks */
    uint32_t parent_a       [ANIMA_MAX_ENTITIES];
    uint32_t parent_b       [ANIMA_MAX_ENTITIES];
} Reproduction;

typedef struct EntityMeta {
    uint32_t age_ticks  [ANIMA_MAX_ENTITIES];
    uint8_t  alive      [ANIMA_MAX_ENTITIES];
    uint8_t  species_id [ANIMA_MAX_ENTITIES];  /* index into species table */
    uint8_t  _pad[2 * ANIMA_MAX_ENTITIES];
} EntityMeta;

/* ── Entity Manager ─────────────────────────────────────────────────────── */

typedef struct EntityManager {
    /* Component pools */
    CoreVitals       vitals;
    Metabolism       metabolism;
    Hormones         hormones;
    Thermoregulation thermoreg;
    Reproduction     reproduction;
    EntityMeta       meta;

    /* Slot management */
    uint32_t   ids       [ANIMA_MAX_ENTITIES];  /* sparse map slot -> entity_id */
    uint32_t   slot_of   [ANIMA_MAX_ENTITIES];  /* entity_id -> slot (if alive) */
    uint32_t   count;                           /* active entities */
    uint32_t   next_id;

    /* RNG state (xoshiro256**) */
    uint64_t   rng[4];
} EntityManager;
