/**
 * entity_manager.cpp — EntityManager: slot allocation, creation, destruction.
 */
#include "anima/ecs_types.h"
#include "anima/anima_core.h"
#include <string.h>
#include <stdio.h>

/* Global singleton (single-world simulation). */
static EntityManager g_em;
static bool g_initialized = false;

/* ── xoshiro256** RNG ──────────────────────────────────────────────────── */
static inline uint64_t rotl(uint64_t x, int k) {
    return (x << k) | (x >> (64 - k));
}
static uint64_t rng_next(uint64_t s[4]) {
    uint64_t r = rotl(s[1] * 5, 7) * 9;
    uint64_t t = s[1] << 17;
    s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3];
    s[2] ^= t; s[3] = rotl(s[3], 45);
    return r;
}
static float rng_float(uint64_t s[4]) {
    return (float)(rng_next(s) >> 11) * (1.0f / (float)(1ULL << 53));
}

/* ── Init / shutdown ────────────────────────────────────────────────────── */
int anima_init(uint32_t /*max_entities*/, uint64_t seed) {
    memset(&g_em, 0, sizeof(g_em));
    g_em.next_id = 1;
    /* Seed xoshiro256** */
    g_em.rng[0] = seed ^ 0x9e3779b97f4a7c15ULL;
    g_em.rng[1] = seed * 0x6c62272e07bb0142ULL + 1;
    g_em.rng[2] = seed ^ 0xbf58476d1ce4e5b9ULL;
    g_em.rng[3] = seed * 0x94d049bb133111ebULL ^ 0xff;
    g_initialized = true;
    return 0;
}

void anima_shutdown(void) {
    g_initialized = false;
    memset(&g_em, 0, sizeof(g_em));
}

EntityId anima_create_entity(const char* /*species*/) {
    if (!g_initialized || g_em.count >= ANIMA_MAX_ENTITIES)
        return ANIMA_INVALID_ENTITY;

    uint32_t slot = g_em.count;
    EntityId id = g_em.next_id++;

    g_em.ids[slot] = id;
    g_em.slot_of[id % ANIMA_MAX_ENTITIES] = slot;
    g_em.count++;

    /* Initialize with healthy defaults */
    g_em.vitals.energy[slot]        = 0.8f + rng_float(g_em.rng) * 0.2f;
    g_em.vitals.hydration[slot]     = 0.8f + rng_float(g_em.rng) * 0.2f;
    g_em.vitals.sleep_toxins[slot]  = rng_float(g_em.rng) * 0.1f;
    g_em.vitals.injury[slot]        = 0.0f;

    g_em.metabolism.energy_decay_rate[slot]    = 0.0003f + rng_float(g_em.rng) * 0.0002f;
    g_em.metabolism.hydration_decay_rate[slot] = 0.0004f + rng_float(g_em.rng) * 0.0002f;
    g_em.metabolism.metabolic_rate[slot]       = 0.9f + rng_float(g_em.rng) * 0.2f;

    g_em.hormones.cortisol[slot]   = 0.05f;
    g_em.hormones.dopamine[slot]   = 0.5f;
    g_em.hormones.endorphin[slot]  = 0.3f;
    g_em.hormones.adrenaline[slot] = 0.0f;

    g_em.thermoreg.body_temp[slot]    = 37.0f;
    g_em.thermoreg.ambient_temp[slot] = 20.0f;
    g_em.thermoreg.insulation[slot]   = 0.5f;

    g_em.reproduction.fertility[slot]        = 0.5f;
    g_em.reproduction.mating_cooldown[slot]  = 0;

    g_em.meta.alive[slot]      = 1;
    g_em.meta.age_ticks[slot]  = 0;
    g_em.meta.species_id[slot] = 0;

    return id;
}

void anima_destroy_entity(EntityId id) {
    if (!g_initialized || id == ANIMA_INVALID_ENTITY)
        return;
    uint32_t slot = g_em.slot_of[id % ANIMA_MAX_ENTITIES];
    if (g_em.ids[slot] != id)
        return;  /* Already gone */

    /* Swap with last slot for O(1) removal */
    uint32_t last = g_em.count - 1;
    if (slot != last) {
        EntityId last_id = g_em.ids[last];
        /* Copy component data */
        g_em.vitals.energy[slot]        = g_em.vitals.energy[last];
        g_em.vitals.hydration[slot]     = g_em.vitals.hydration[last];
        g_em.vitals.sleep_toxins[slot]  = g_em.vitals.sleep_toxins[last];
        g_em.vitals.injury[slot]        = g_em.vitals.injury[last];
        g_em.metabolism.energy_decay_rate[slot]    = g_em.metabolism.energy_decay_rate[last];
        g_em.metabolism.hydration_decay_rate[slot] = g_em.metabolism.hydration_decay_rate[last];
        g_em.metabolism.metabolic_rate[slot]       = g_em.metabolism.metabolic_rate[last];
        g_em.hormones.cortisol[slot]   = g_em.hormones.cortisol[last];
        g_em.hormones.dopamine[slot]   = g_em.hormones.dopamine[last];
        g_em.hormones.endorphin[slot]  = g_em.hormones.endorphin[last];
        g_em.hormones.adrenaline[slot] = g_em.hormones.adrenaline[last];
        g_em.thermoreg.body_temp[slot]    = g_em.thermoreg.body_temp[last];
        g_em.thermoreg.ambient_temp[slot] = g_em.thermoreg.ambient_temp[last];
        g_em.thermoreg.insulation[slot]   = g_em.thermoreg.insulation[last];
        g_em.reproduction.fertility[slot]       = g_em.reproduction.fertility[last];
        g_em.reproduction.mating_cooldown[slot] = g_em.reproduction.mating_cooldown[last];
        g_em.meta.alive[slot]      = g_em.meta.alive[last];
        g_em.meta.age_ticks[slot]  = g_em.meta.age_ticks[last];
        g_em.meta.species_id[slot] = g_em.meta.species_id[last];
        g_em.ids[slot]   = last_id;
        g_em.slot_of[last_id % ANIMA_MAX_ENTITIES] = slot;
    }
    g_em.count--;
    /* Invalidate the now-empty tail slot so stale lookups return -1 */
    if (g_em.count < ANIMA_MAX_ENTITIES)
        g_em.ids[g_em.count] = ANIMA_INVALID_ENTITY;
}

int anima_get_state(EntityId id, AnimaBodyState* out) {
    if (!g_initialized || !out || id == ANIMA_INVALID_ENTITY)
        return -1;
    uint32_t slot = g_em.slot_of[id % ANIMA_MAX_ENTITIES];
    if (g_em.ids[slot] != id)
        return -1;
    out->id           = id;
    out->energy       = g_em.vitals.energy[slot];
    out->hydration    = g_em.vitals.hydration[slot];
    out->sleep_toxins = g_em.vitals.sleep_toxins[slot];
    out->cortisol     = g_em.hormones.cortisol[slot];
    out->dopamine     = g_em.hormones.dopamine[slot];
    out->endorphin    = g_em.hormones.endorphin[slot];
    out->body_temp    = g_em.thermoreg.body_temp[slot];
    out->injury       = g_em.vitals.injury[slot];
    out->age_ticks    = g_em.meta.age_ticks[slot];
    out->alive        = g_em.meta.alive[slot];
    return 0;
}

uint32_t anima_get_states_batch(const EntityId* ids, uint32_t count,
                                 AnimaBodyState* buf) {
    uint32_t filled = 0;
    for (uint32_t i = 0; i < count; i++) {
        if (anima_get_state(ids[i], &buf[filled]) == 0)
            filled++;
    }
    return filled;
}

void anima_apply_event(EntityId id, const AnimaEvent* ev) {
    if (!g_initialized || !ev || id == ANIMA_INVALID_ENTITY)
        return;
    uint32_t slot = g_em.slot_of[id % ANIMA_MAX_ENTITIES];
    if (g_em.ids[slot] != id || !g_em.meta.alive[slot])
        return;

    const char* t = ev->type;
    float amt = ev->amount;

    if (strcmp(t, "eat") == 0) {
        g_em.vitals.energy[slot] += amt;
        if (g_em.vitals.energy[slot] > 1.0f) g_em.vitals.energy[slot] = 1.0f;
        g_em.hormones.dopamine[slot] += 0.05f;
    } else if (strcmp(t, "drink") == 0) {
        g_em.vitals.hydration[slot] += amt;
        if (g_em.vitals.hydration[slot] > 1.0f) g_em.vitals.hydration[slot] = 1.0f;
    } else if (strcmp(t, "sleep") == 0) {
        g_em.vitals.sleep_toxins[slot] -= amt;
        if (g_em.vitals.sleep_toxins[slot] < 0.0f) g_em.vitals.sleep_toxins[slot] = 0.0f;
        g_em.hormones.cortisol[slot] *= 0.95f;
    } else if (strcmp(t, "damage") == 0) {
        g_em.vitals.injury[slot] += amt;
        if (g_em.vitals.injury[slot] > 1.0f) g_em.vitals.injury[slot] = 1.0f;
        g_em.vitals.energy[slot] -= amt * 0.3f;
        g_em.hormones.cortisol[slot] += 0.15f;
        g_em.hormones.adrenaline[slot] += 0.2f;
    } else if (strcmp(t, "temperature_change") == 0) {
        g_em.thermoreg.ambient_temp[slot] += amt;
    } else if (strcmp(t, "player_reward") == 0) {
        g_em.hormones.dopamine[slot] += amt;
        if (g_em.hormones.dopamine[slot] > 1.0f) g_em.hormones.dopamine[slot] = 1.0f;
    } else if (strcmp(t, "player_punish") == 0) {
        g_em.hormones.cortisol[slot] += amt;
        if (g_em.hormones.cortisol[slot] > 1.0f) g_em.hormones.cortisol[slot] = 1.0f;
    }

    /* Clamp all to valid ranges */
    if (g_em.hormones.dopamine[slot]  > 1.0f) g_em.hormones.dopamine[slot]  = 1.0f;
    if (g_em.hormones.dopamine[slot]  < 0.0f) g_em.hormones.dopamine[slot]  = 0.0f;
    if (g_em.hormones.cortisol[slot]  > 1.0f) g_em.hormones.cortisol[slot]  = 1.0f;
    if (g_em.hormones.cortisol[slot]  < 0.0f) g_em.hormones.cortisol[slot]  = 0.0f;
    if (g_em.hormones.adrenaline[slot]> 1.0f) g_em.hormones.adrenaline[slot]= 1.0f;
    if (g_em.hormones.adrenaline[slot]< 0.0f) g_em.hormones.adrenaline[slot]= 0.0f;
}

uint32_t anima_get_observation(EntityId id, float* obs_buf, uint32_t buf_size) {
    if (buf_size < ANIMA_OBS_DIM) return 0;
    AnimaBodyState s;
    if (anima_get_state(id, &s) != 0) return 0;
    obs_buf[0] = s.energy;
    obs_buf[1] = s.hydration;
    obs_buf[2] = s.sleep_toxins;
    obs_buf[3] = s.cortisol;
    obs_buf[4] = s.dopamine;
    obs_buf[5] = (s.body_temp - 30.0f) / 20.0f;  /* normalize 30..50 → 0..1 */
    obs_buf[6] = 0.0f;  /* nearby_count (filled by GDExtension wrapper) */
    obs_buf[7] = 0.0f;  /* food_dist_inv */
    obs_buf[8] = 0.0f;  /* water_dist_inv */
    obs_buf[9] = 0.0f;  /* time_of_day_norm */
    return ANIMA_OBS_DIM;
}

/* Expose g_em pointer for system modules */
EntityManager* anima_get_manager(void) { return &g_em; }
