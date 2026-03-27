#pragma once
/**
 * anima_core.h — Public C API for the ANIMA body simulation ECS.
 *
 * This header is the boundary between Godot GDScript/GDExtension callers and
 * the C++ simulation engine.  All types are C-compatible for FFI safety.
 */

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Entity IDs ─────────────────────────────────────────────────────────── */
typedef uint32_t EntityId;
#define ANIMA_INVALID_ENTITY ((EntityId)0)

/* ── Core vitals snapshot (POD, cache-friendly) ─────────────────────────── */
typedef struct AnimaBodyState {
    EntityId  id;
    float     energy;           /* 0..1  blood glucose / fat reserves */
    float     hydration;        /* 0..1  body water */
    float     sleep_toxins;     /* 0..1  adenosine accumulation */
    float     cortisol;         /* 0..1  stress hormone */
    float     dopamine;         /* 0..1  reward signal */
    float     endorphin;        /* 0..1  pain-relief / pleasure */
    float     body_temp;        /* °C   ~35..42 viable range */
    float     injury;           /* 0..1  cumulative damage */
    uint32_t  age_ticks;
    uint8_t   alive;            /* bool */
    uint8_t   _pad[3];
} AnimaBodyState;

/* ── Event payload ──────────────────────────────────────────────────────── */
typedef struct AnimaEvent {
    const char* type;           /* "eat", "drink", "sleep", "damage", ... */
    float       amount;
    float       param1;
    float       param2;
} AnimaEvent;

/* ── Batch step result ──────────────────────────────────────────────────── */
typedef struct AnimaBatchResult {
    uint32_t  entities_updated;
    uint32_t  deaths_this_tick;
    double    wall_time_ms;
} AnimaBatchResult;

/* ── Init / shutdown ────────────────────────────────────────────────────── */
int             anima_init(uint32_t max_entities, uint64_t seed);
void            anima_shutdown(void);

/* ── Entity lifecycle ───────────────────────────────────────────────────── */
EntityId        anima_create_entity(const char* species);
void            anima_destroy_entity(EntityId id);

/* ── State access ───────────────────────────────────────────────────────── */
int             anima_get_state(EntityId id, AnimaBodyState* out);
/* Batch read: fills buf[0..count-1], returns number actually filled */
uint32_t        anima_get_states_batch(const EntityId* ids, uint32_t count,
                                        AnimaBodyState* buf);

/* ── Events ─────────────────────────────────────────────────────────────── */
void            anima_apply_event(EntityId id, const AnimaEvent* ev);

/* ── Simulation tick ────────────────────────────────────────────────────── */
AnimaBatchResult anima_batch_step(float dt);

/* ── Observation vector for RL ──────────────────────────────────────────── */
/* Fills obs_buf with OBS_DIM floats; returns OBS_DIM or 0 on error. */
#define ANIMA_OBS_DIM 10
uint32_t        anima_get_observation(EntityId id, float* obs_buf,
                                       uint32_t buf_size);

/* ── Telemetry / profiling ──────────────────────────────────────────────── */
typedef struct AnimaProfileSnapshot {
    double metabolism_ms;
    double hormones_ms;
    double thermoreg_ms;
    double reproduction_ms;
    double flush_ms;
    double total_ms;
} AnimaProfileSnapshot;
void            anima_get_profile(AnimaProfileSnapshot* out);

#ifdef __cplusplus
}
#endif
