/**
 * test_ecs.cpp — Unit tests for deterministic ECS behavior.
 * Compile standalone:
 *   g++ -std=c++17 -I../include src/ecs/entity_manager.cpp \
 *       src/systems/systems.cpp tests/test_ecs.cpp -lm -o test_ecs
 */
#include "anima/anima_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <assert.h>
#include <time.h>

#define TEST(name) static void test_##name()
#define RUN(name)  do { printf("  %-40s", #name); test_##name(); printf("PASS\n"); } while(0)
#define ASSERT_NEAR(a, b, eps) \
    do { if (fabsf((a)-(b)) > (eps)) { \
        fprintf(stderr, "\n  FAIL at %s:%d: |%.6f - %.6f| > %.6f\n", \
            __FILE__, __LINE__, (float)(a), (float)(b), (float)(eps)); \
        exit(1); } } while(0)
#define ASSERT_TRUE(cond) \
    do { if (!(cond)) { \
        fprintf(stderr, "\n  FAIL at %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        exit(1); } } while(0)

/* ── Test: create / destroy entity ─────────────────────────────────────── */
TEST(create_destroy) {
    anima_init(256, 42ULL);
    EntityId a = anima_create_entity("zoi");
    EntityId b = anima_create_entity("zoi");
    ASSERT_TRUE(a != ANIMA_INVALID_ENTITY);
    ASSERT_TRUE(b != ANIMA_INVALID_ENTITY);
    ASSERT_TRUE(a != b);

    AnimaBodyState sa, sb;
    ASSERT_TRUE(anima_get_state(a, &sa) == 0);
    ASSERT_TRUE(anima_get_state(b, &sb) == 0);
    ASSERT_TRUE(sa.alive);
    ASSERT_TRUE(sb.alive);

    anima_destroy_entity(a);
    ASSERT_TRUE(anima_get_state(a, &sa) != 0);  /* Should fail: entity gone */
    ASSERT_TRUE(anima_get_state(b, &sb) == 0);  /* b still alive */
    anima_shutdown();
}

/* ── Test: metabolism decay ─────────────────────────────────────────────── */
TEST(metabolism_decay) {
    anima_init(64, 1ULL);
    EntityId id = anima_create_entity("zoi");

    AnimaBodyState s0;
    anima_get_state(id, &s0);

    /* Run 15 ticks (1 second at 15 Hz) */
    for (int i = 0; i < 15; i++)
        anima_batch_step(1.0f / 15.0f);

    AnimaBodyState s1;
    anima_get_state(id, &s1);

    /* Energy and hydration must have decreased */
    ASSERT_TRUE(s1.energy < s0.energy);
    ASSERT_TRUE(s1.hydration < s0.hydration);
    /* Sleep toxins must have increased */
    ASSERT_TRUE(s1.sleep_toxins > s0.sleep_toxins);
    ASSERT_TRUE(s1.age_ticks == 15);
    anima_shutdown();
}

/* ── Test: eat event increases energy ─────────────────────────────────── */
TEST(eat_event) {
    anima_init(64, 2ULL);
    EntityId id = anima_create_entity("zoi");

    /* Drain energy first */
    AnimaEvent dmg = { "damage", 0.5f, 0.0f, 0.0f };
    anima_apply_event(id, &dmg);

    AnimaBodyState before;
    anima_get_state(id, &before);

    AnimaEvent eat = { "eat", 0.3f, 0.0f, 0.0f };
    anima_apply_event(id, &eat);

    AnimaBodyState after;
    anima_get_state(id, &after);

    ASSERT_TRUE(after.energy > before.energy);
    anima_shutdown();
}

/* ── Test: starvation causes death ─────────────────────────────────────── */
TEST(starvation_death) {
    anima_init(64, 3ULL);
    EntityId id = anima_create_entity("zoi");

    /* Drain energy completely (apply enough damage to zero out energy) */
    for (int i = 0; i < 5; i++) {
        AnimaEvent ev = { "damage", 1.0f, 0.0f, 0.0f };
        anima_apply_event(id, &ev);
    }

    /* One tick should detect death and remove entity */
    anima_batch_step(1.0f / 15.0f);

    AnimaBodyState s;
    /* Entity should be gone */
    ASSERT_TRUE(anima_get_state(id, &s) != 0);
    anima_shutdown();
}

/* ── Test: deterministic replay ─────────────────────────────────────────── */
TEST(deterministic_replay) {
    /* Two simulations with same seed must produce identical states */
    float energy_a, energy_b;
    const uint64_t SEED = 0xDEADBEEFCAFE;
    const int STEPS = 30;

    /* Run A */
    anima_init(64, SEED);
    EntityId id_a = anima_create_entity("zoi");
    for (int i = 0; i < STEPS; i++) anima_batch_step(1.0f / 15.0f);
    AnimaBodyState sa;
    anima_get_state(id_a, &sa);
    energy_a = sa.energy;
    anima_shutdown();

    /* Run B */
    anima_init(64, SEED);
    EntityId id_b = anima_create_entity("zoi");
    for (int i = 0; i < STEPS; i++) anima_batch_step(1.0f / 15.0f);
    AnimaBodyState sb;
    anima_get_state(id_b, &sb);
    energy_b = sb.energy;
    anima_shutdown();

    ASSERT_NEAR(energy_a, energy_b, 1e-6f);
}

/* ── Test: hypothermia stress ────────────────────────────────────────────── */
TEST(hypothermia) {
    anima_init(64, 7ULL);
    EntityId id = anima_create_entity("zoi");

    /* Force extreme cold */
    AnimaEvent cold = { "temperature_change", -20.0f, 0.0f, 0.0f };
    anima_apply_event(id, &cold);

    /* Run enough ticks for temperature to drop */
    AnimaBodyState s0;
    anima_get_state(id, &s0);
    float initial_energy = s0.energy;

    for (int i = 0; i < 60; i++)
        anima_batch_step(1.0f / 15.0f);

    AnimaBodyState s1;
    int still_alive = (anima_get_state(id, &s1) == 0);
    /* Either dead or energy is lower due to cold stress */
    ASSERT_TRUE(!still_alive || s1.energy < initial_energy);
    anima_shutdown();
}

/* ── Test: batch observation vector ────────────────────────────────────── */
TEST(observation_vector) {
    anima_init(64, 9ULL);
    EntityId id = anima_create_entity("zoi");
    float obs[ANIMA_OBS_DIM];
    uint32_t n = anima_get_observation(id, obs, ANIMA_OBS_DIM);
    ASSERT_TRUE(n == ANIMA_OBS_DIM);
    /* Energy should be in [0,1] */
    ASSERT_TRUE(obs[0] >= 0.0f && obs[0] <= 1.0f);
    ASSERT_TRUE(obs[1] >= 0.0f && obs[1] <= 1.0f);
    anima_shutdown();
}

/* ── Test: performance benchmark ──────────────────────────────────────── */
TEST(performance_100_zoi) {
    anima_init(512, 99ULL);
    for (int i = 0; i < 100; i++)
        anima_create_entity("zoi");

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int step = 0; step < 100; step++)
        anima_batch_step(1.0f / 15.0f);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double elapsed_ms = (t1.tv_sec - t0.tv_sec) * 1000.0 +
                        (t1.tv_nsec - t0.tv_nsec) / 1.0e6;
    double per_step_ms = elapsed_ms / 100.0;
    printf("[%.3f ms/step] ", per_step_ms);
    /* Target: < 1 ms per step for 100 Zoi */
    ASSERT_TRUE(per_step_ms < 10.0);  /* Generous budget for CI */
    anima_shutdown();
}

/* ── Main ────────────────────────────────────────────────────────────────── */
int main(void) {
    printf("=== ANIMA ECS Unit Tests ===\n");
    RUN(create_destroy);
    RUN(metabolism_decay);
    RUN(eat_event);
    RUN(starvation_death);
    RUN(deterministic_replay);
    RUN(hypothermia);
    RUN(observation_vector);
    RUN(performance_100_zoi);
    printf("\nAll tests passed.\n");
    return 0;
}
