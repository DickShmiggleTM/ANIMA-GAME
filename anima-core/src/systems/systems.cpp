/**
 * systems.cpp — ECS update kernels: metabolism, hormones, thermoregulation,
 *               reproduction.  All operate on contiguous SoA arrays.
 *
 * Tick loop: update_metabolism → update_hormones → apply_environmental_effects
 *            → resolve_reproduction → flush_state_changes
 */
#include "anima/ecs_types.h"
#include "anima/anima_core.h"
#include <math.h>
#include <string.h>
#include <time.h>

/* Forward declaration */
EntityManager* anima_get_manager(void);

/* ── Profiling counters ─────────────────────────────────────────────────── */
static AnimaProfileSnapshot g_profile;

static double wall_ms() {
#if defined(_WIN32)
    return 0.0;
#elif defined(CLOCK_MONOTONIC)
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1.0e6;
#else
    return 0.0;
#endif
}

/* ── Clamp helpers ─────────────────────────────────────────────────────── */
static inline float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
static inline float lerpf(float a, float b, float t) {
    return a + (b - a) * t;
}

/* ── update_metabolism ──────────────────────────────────────────────────── */
static void update_metabolism(EntityManager* em, float dt) {
    double t0 = wall_ms();
    for (uint32_t i = 0; i < em->count; i++) {
        if (!em->meta.alive[i]) continue;
        float mr = em->metabolism.metabolic_rate[i];
        /* Fatigue degrades metabolic efficiency */
        mr *= (1.0f - em->vitals.sleep_toxins[i] * 0.3f);

        em->vitals.energy[i] -= em->metabolism.energy_decay_rate[i] * mr * dt;
        em->vitals.hydration[i] -= em->metabolism.hydration_decay_rate[i] * mr * dt;
        /* Sleep toxins accumulate while awake (assume always awake unless sleeping) */
        em->vitals.sleep_toxins[i] += 0.0003f * dt;

        em->vitals.energy[i]       = clampf(em->vitals.energy[i], 0.0f, 1.0f);
        em->vitals.hydration[i]    = clampf(em->vitals.hydration[i], 0.0f, 1.0f);
        em->vitals.sleep_toxins[i] = clampf(em->vitals.sleep_toxins[i], 0.0f, 1.0f);
        em->meta.age_ticks[i]++;
    }
    g_profile.metabolism_ms = wall_ms() - t0;
}

/* ── update_hormones ────────────────────────────────────────────────────── */
static void update_hormones(EntityManager* em, float dt) {
    double t0 = wall_ms();
    for (uint32_t i = 0; i < em->count; i++) {
        if (!em->meta.alive[i]) continue;

        /* Cortisol rises under hunger/thirst stress */
        float hunger_stress  = 1.0f - em->vitals.energy[i];
        float thirst_stress  = 1.0f - em->vitals.hydration[i];
        float fatigue_stress = em->vitals.sleep_toxins[i];
        float injury_stress  = em->vitals.injury[i];
        float total_stress   = clampf(
            hunger_stress * 0.3f + thirst_stress * 0.3f +
            fatigue_stress * 0.2f + injury_stress * 0.2f,
            0.0f, 1.0f);

        float cortisol_target = total_stress;
        em->hormones.cortisol[i] = lerpf(em->hormones.cortisol[i],
                                         cortisol_target, 0.05f * dt * 15.0f);

        /* Dopamine decays toward baseline when not rewarded */
        float dopamine_baseline = 1.0f - em->hormones.cortisol[i] * 0.5f;
        em->hormones.dopamine[i] = lerpf(em->hormones.dopamine[i],
                                          dopamine_baseline, 0.02f * dt * 15.0f);

        /* Adrenaline decays quickly */
        em->hormones.adrenaline[i] *= powf(0.85f, dt * 15.0f);

        /* Endorphin decays toward 0.1 baseline */
        em->hormones.endorphin[i] = lerpf(em->hormones.endorphin[i],
                                           0.1f, 0.01f * dt * 15.0f);

        /* Clamp */
        em->hormones.cortisol[i]   = clampf(em->hormones.cortisol[i],   0.0f, 1.0f);
        em->hormones.dopamine[i]   = clampf(em->hormones.dopamine[i],   0.0f, 1.0f);
        em->hormones.adrenaline[i] = clampf(em->hormones.adrenaline[i], 0.0f, 1.0f);
        em->hormones.endorphin[i]  = clampf(em->hormones.endorphin[i],  0.0f, 1.0f);
    }
    g_profile.hormones_ms = wall_ms() - t0;
}

/* ── apply_environmental_effects ────────────────────────────────────────── */
static void apply_environmental_effects(EntityManager* em, float dt) {
    double t0 = wall_ms();
    const float HEAT_EXCHANGE_RATE = 0.01f;

    for (uint32_t i = 0; i < em->count; i++) {
        if (!em->meta.alive[i]) continue;

        /* Thermoregulation: body temp drifts toward ambient, resisted by insulation */
        float diff = em->thermoreg.ambient_temp[i] - em->thermoreg.body_temp[i];
        float insulation = em->thermoreg.insulation[i];
        em->thermoreg.body_temp[i] += diff * HEAT_EXCHANGE_RATE * (1.0f - insulation) * dt * 15.0f;

        /* Extreme temperature costs energy */
        float temp_stress = 0.0f;
        if (em->thermoreg.body_temp[i] < 35.0f)
            temp_stress = (35.0f - em->thermoreg.body_temp[i]) * 0.05f;
        else if (em->thermoreg.body_temp[i] > 39.5f)
            temp_stress = (em->thermoreg.body_temp[i] - 39.5f) * 0.05f;
        em->vitals.energy[i] = clampf(em->vitals.energy[i] - temp_stress * dt, 0.0f, 1.0f);

        /* Injury recovery (slow) */
        em->vitals.injury[i] = clampf(em->vitals.injury[i] - 0.0001f * dt, 0.0f, 1.0f);
    }
    g_profile.thermoreg_ms = wall_ms() - t0;
}

/* ── resolve_reproduction ───────────────────────────────────────────────── */
static void resolve_reproduction(EntityManager* em, float dt) {
    double t0 = wall_ms();
    for (uint32_t i = 0; i < em->count; i++) {
        if (!em->meta.alive[i]) continue;
        if (em->reproduction.mating_cooldown[i] > 0)
            em->reproduction.mating_cooldown[i]--;
        /* Fertility improves when healthy */
        float health = (em->vitals.energy[i] + em->vitals.hydration[i]) * 0.5f;
        em->reproduction.fertility[i] = lerpf(em->reproduction.fertility[i],
                                               health, 0.001f * dt * 15.0f);
    }
    g_profile.reproduction_ms = wall_ms() - t0;
}

/* ── flush_state_changes (handle deaths) ────────────────────────────────── */
static uint32_t flush_state_changes(EntityManager* em) {
    double t0 = wall_ms();
    uint32_t deaths = 0;
    /* Collect IDs to kill (can't destroy in-place during iteration) */
    static EntityId to_kill[ANIMA_MAX_ENTITIES];
    uint32_t kill_count = 0;

    for (uint32_t i = 0; i < em->count; i++) {
        if (!em->meta.alive[i]) continue;
        bool dead = (em->vitals.energy[i] <= 0.0f ||
                     em->vitals.hydration[i] <= 0.0f ||
                     em->thermoreg.body_temp[i] < 28.0f ||
                     em->thermoreg.body_temp[i] > 42.0f);
        if (dead && kill_count < ANIMA_MAX_ENTITIES) {
            to_kill[kill_count++] = em->ids[i];
        }
    }
    for (uint32_t k = 0; k < kill_count; k++) {
        anima_destroy_entity(to_kill[k]);
        deaths++;
    }
    g_profile.flush_ms = wall_ms() - t0;
    return deaths;
}

/* ── Main tick ──────────────────────────────────────────────────────────── */
AnimaBatchResult anima_batch_step(float dt) {
    double t0 = wall_ms();
    EntityManager* em = anima_get_manager();
    uint32_t before = em->count;

    update_metabolism(em, dt);
    update_hormones(em, dt);
    apply_environmental_effects(em, dt);
    resolve_reproduction(em, dt);
    uint32_t deaths = flush_state_changes(em);

    double total = wall_ms() - t0;
    g_profile.total_ms = total;

    AnimaBatchResult r;
    r.entities_updated = before;
    r.deaths_this_tick = deaths;
    r.wall_time_ms     = total;
    return r;
}

void anima_get_profile(AnimaProfileSnapshot* out) {
    if (out) *out = g_profile;
}
