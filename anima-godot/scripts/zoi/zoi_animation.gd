## ZoiAnimation — deterministic animation state machine.
## Maps intent strings to animation playback on the AnimationPlayer.
class_name ZoiAnimation
extends AnimationPlayer

# Intent → animation name mapping
const INTENT_ANIM := {
	"idle":      "idle",
	"eat":       "eat",
	"drink":     "drink",
	"rest":      "rest",
	"wander":    "walk",
	"socialize": "wave",
	"flee":      "run",
	"build":     "build",
	"share":     "give",
	"call":      "gesture",
}

var _current_intent := "idle"

func play_intent(intent: String) -> void:
	if intent == _current_intent:
		return
	_current_intent = intent
	var anim_name: String = INTENT_ANIM.get(intent, "idle")
	# Only play if animation exists; otherwise stay on current
	if has_animation(anim_name):
		play(anim_name)

func _ready() -> void:
	# Create procedural placeholder animations for cube proxy
	_add_placeholder_animations()
	play("idle")

func _add_placeholder_animations() -> void:
	var lib := AnimationLibrary.new()
	for anim_name in INTENT_ANIM.values():
		if not lib.has_animation(anim_name):
			var a := Animation.new()
			a.length = 1.0
			a.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(anim_name, a)
	add_animation_library("", lib)
