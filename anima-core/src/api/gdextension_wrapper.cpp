/**
 * gdextension_wrapper.cpp — Godot GDExtension binding for AnimaCore.
 *
 * Exposes the C simulation API to GDScript as an Object subclass
 * "AnimaCoreECS".  This file is only compiled when building with
 * godot-cpp; the C API (anima_core.h) remains portable.
 */
#ifdef ANIMA_BUILD_GDEXTENSION
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>
#include "anima/anima_core.h"

using namespace godot;

class AnimaCoreECS : public Object {
    GDCLASS(AnimaCoreECS, Object)

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("init", "max_entities", "seed"),
            &AnimaCoreECS::init);
        ClassDB::bind_method(D_METHOD("create_entity", "id", "species", "genetics"),
            &AnimaCoreECS::create_entity);
        ClassDB::bind_method(D_METHOD("destroy_entity", "id"),
            &AnimaCoreECS::destroy_entity);
        ClassDB::bind_method(D_METHOD("get_state", "id"),
            &AnimaCoreECS::get_state);
        ClassDB::bind_method(D_METHOD("apply_event", "id", "event_type", "params"),
            &AnimaCoreECS::apply_event);
        ClassDB::bind_method(D_METHOD("batch_step", "dt"),
            &AnimaCoreECS::batch_step);
        ClassDB::bind_method(D_METHOD("get_observation", "id"),
            &AnimaCoreECS::get_observation);
        ClassDB::bind_method(D_METHOD("get_profile"),
            &AnimaCoreECS::get_profile);
    }

public:
    AnimaCoreECS() {
        anima_init(1024, 12345678ULL);
    }
    ~AnimaCoreECS() {
        anima_shutdown();
    }

    int init(int max_entities, int64_t seed) {
        anima_shutdown();
        return anima_init((uint32_t)max_entities, (uint64_t)seed);
    }

    /* Note: GDScript passes id as int; we use it only for tracking.
       The C API assigns its own IDs, so we return the new one. */
    int create_entity(int /*hint_id*/, const String& species, const Dictionary& /*genetics*/) {
        CharString cs = species.utf8();
        return (int)anima_create_entity(cs.get_data());
    }

    void destroy_entity(int id) {
        anima_destroy_entity((EntityId)id);
    }

    Dictionary get_state(int id) {
        AnimaBodyState s;
        Dictionary d;
        if (anima_get_state((EntityId)id, &s) != 0)
            return d;
        d["id"]           = (int)s.id;
        d["energy"]       = (float)s.energy;
        d["hydration"]    = (float)s.hydration;
        d["sleep_toxins"] = (float)s.sleep_toxins;
        d["cortisol"]     = (float)s.cortisol;
        d["dopamine"]     = (float)s.dopamine;
        d["endorphin"]    = (float)s.endorphin;
        d["body_temp"]    = (float)s.body_temp;
        d["body_temp_norm"] = (float)((s.body_temp - 30.0f) / 20.0f);
        d["injury"]       = (float)s.injury;
        d["age_ticks"]    = (int)s.age_ticks;
        d["alive"]        = (bool)s.alive;
        return d;
    }

    void apply_event(int id, const String& event_type, const Dictionary& params) {
        AnimaEvent ev;
        CharString cs = event_type.utf8();
        ev.type   = cs.get_data();
        ev.amount = (float)(double)params.get("amount", 0.2);
        ev.param1 = (float)(double)params.get("param1", 0.0);
        ev.param2 = (float)(double)params.get("param2", 0.0);
        anima_apply_event((EntityId)id, &ev);
    }

    Dictionary batch_step(float dt) {
        AnimaBatchResult r = anima_batch_step(dt);
        Dictionary d;
        d["entities_updated"] = (int)r.entities_updated;
        d["deaths_this_tick"] = (int)r.deaths_this_tick;
        d["wall_time_ms"]     = (float)r.wall_time_ms;
        return d;
    }

    Array get_observation(int id) {
        float buf[ANIMA_OBS_DIM];
        uint32_t n = anima_get_observation((EntityId)id, buf, ANIMA_OBS_DIM);
        Array a;
        for (uint32_t i = 0; i < n; i++) a.push_back(buf[i]);
        return a;
    }

    Dictionary get_profile() {
        AnimaProfileSnapshot p;
        anima_get_profile(&p);
        Dictionary d;
        d["metabolism_ms"]    = (float)p.metabolism_ms;
        d["hormones_ms"]      = (float)p.hormones_ms;
        d["thermoreg_ms"]     = (float)p.thermoreg_ms;
        d["reproduction_ms"]  = (float)p.reproduction_ms;
        d["flush_ms"]         = (float)p.flush_ms;
        d["total_ms"]         = (float)p.total_ms;
        return d;
    }
};

/* ── GDExtension entry points ─────────────────────────────────────────── */
extern "C" {

GDExtensionBool GDE_EXPORT anima_core_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    const GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization* r_initialization)
{
    godot::GDExtensionBinding::InitObject init_obj(
        p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer([](godot::ModuleInitializationLevel level) {
        if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
            godot::ClassDB::register_class<AnimaCoreECS>();
        }
    });
    init_obj.register_terminator([](godot::ModuleInitializationLevel) {});
    init_obj.set_minimum_library_initialization_level(
        godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}

} /* extern "C" */

#endif /* ANIMA_BUILD_GDEXTENSION */
