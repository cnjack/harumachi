extends Node
## Music, ambience and sound effects. Every sound is synthesized by art/tools/synth_audio.py.
## Buses: Master (limiter) <- Music (low-pass while indoors), Ambience, SFX, UI.
## The music tracks are through-composed (MiniMax Music 3 renders with an intro and an ending), so
## instead of a hard loop each one restarts under a LOOP_XF-second crossfade near its end.
## Gameplay stingers only play while `game_on` is true, so booting, tests and loading stay quiet.

const DIR := "res://assets/audio/"
const FADE := 1.8
const OFF_DB := -60.0
const LOOP_XF := 3.0
## A stinger is skipped while a stronger one is still ringing.
const STING_RANK := {"step": 0, "item": 1, "coin": 1, "save": 1, "sparkle": 1, "quest_accept": 2, "quest_done": 3, "fanfare": 4}
const STING_DB := {"step": -8.0, "item": -5.0, "coin": -6.0, "save": -6.0, "sparkle": -7.0, "quest_accept": -4.0, "quest_done": -3.0, "fanfare": -2.0}
const MUSIC_DB := {"title": -3.0, "day": -4.0, "market": -4.0, "ending": -2.0, "shop": -6.0, "night": -5.0, "rain": -1.0,
	"farm": -4.5, "memory": -4.0, "prologue": -2.0, "obon": -3.0, "tsukimi": -3.5}
const AMB_DB := {"day": 0.0, "evening": 0.0, "room": 0.0, "farm": 0.0, "night": -1.0, "rain": -1.0}
const SURFACES := ["stone", "gravel", "grass", "wood", "tatami"]

var game_on := false
var music_name := ""
var amb_name := ""
var indoor := false

var _music: Array[AudioStreamPlayer] = []
var _mi := 0
var _amb: Array[AudioStreamPlayer] = []
var _ai := 0
var _jingle: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _world_pool: Array[AudioStreamPlayer3D] = []
var _room_reverb: AudioEffectReverb
var _cache := {}
var _lp: AudioEffectLowPassFilter
var _sting_until := 0.0
var _sting_rank := -1
var _last := {}
var _duck := 1.0
var _duck_tw: Tween
var _lp_tw: Tween
var _tw := {}
var _hold := false   # a one-shot cue (the ending) is playing; the looping track waits underneath


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 2:
		_music.append(_player("Music"))
		_amb.append(_player("Ambience"))
	_jingle = _player("Music")
	_voice = _player("Voice")
	_voice.finished.connect(func(): _voice_duck(false))
	for i in 14:
		_pool.append(_player("SFX"))
	var world_fx:=Node3D.new();world_fx.name="WorldEffects";add_child(world_fx)
	for index: int in 12:
		var source:=AudioStreamPlayer3D.new();source.name="Source_%d"%index
		source.bus="Foley";source.unit_size=3.0;source.max_distance=18.0;source.max_db=-2.0
		source.panning_strength=.65;source.attenuation_filter_cutoff_hz=9500
		world_fx.add_child(source);_world_pool.append(source)
	get_tree().node_added.connect(_on_node_added)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _setup_buses() -> void:
	for b in ["Music", "Ambience", "SFX", "UI", "Voice", "Foley"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var mi := AudioServer.get_bus_index("Music")
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 20000.0
	_lp.resonance = 0.5
	AudioServer.add_bus_effect(mi, _lp)
	_room_reverb=AudioEffectReverb.new();_room_reverb.room_size=.32;_room_reverb.damping=.75;_room_reverb.wet=0.0;_room_reverb.dry=1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Foley"),_room_reverb)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)


## Volumes come from GameState.settings (0..1 each); called by GameState.apply_settings().
## `--no-music` (user arg) mutes the music bus, for recording an effects-only stem.
func apply_volumes(s: Dictionary) -> void:
	var master := float(s.get("vol_master", 1.0))
	var music := 0.0 if "--no-music" in OS.get_cmdline_user_args() else float(s.get("vol_music", 0.75))
	var sfx := float(s.get("vol_sfx", 0.8))
	_voice_vol = float(s.get("vol_voice", 0.9))
	_set_bus("Voice", _voice_vol)
	_music_vol = music
	_set_bus("Master", master)
	_set_bus("Music", music * _duck)
	_set_bus("Ambience", sfx * 0.9)
	_set_bus("SFX", sfx)
	_set_bus("Foley",sfx)
	_set_bus("UI", sfx * 0.8)


# ------------------------------------------------------------------ v0.6 voices
var _voice: AudioStreamPlayer
var _voice_vol := 0.9
var _music_vol := 0.75
const VOICE_DIR := "res://assets/audio/voice/"


## Play the recorded line for `text` (Qwen3-TTS, art/tools/voice/gen_voice_lines.py) if there is one.
## Returns its length in seconds, 0 when the line has no voice.
func voice(who: String, text: String) -> float:
	stop_voice()
	# the narrator (旁白) and place descriptions stay text only
	if _voice_vol <= 0.001 or who == "narrator" or who.begins_with("place:"):
		return 0.0
	var path := "%s%s/%s.ogg" % [VOICE_DIR, who, text.md5_text()]
	if not ResourceLoader.exists(path):
		return 0.0
	var st: AudioStream = load(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = false
	_voice.stream = st
	_voice.play()
	_voice_duck(true)
	return st.get_length()


## Length in seconds of the recorded line for `text`, 0 when it has none (the prologue times its panels by it).
func voice_length(who: String, text: String) -> float:
	var path := "%s%s/%s.ogg" % [VOICE_DIR, who, text.md5_text()]
	if _voice_vol <= 0.001 or not ResourceLoader.exists(path):
		return 0.0
	return (load(path) as AudioStream).get_length()


func voice_playing() -> bool:
	return _voice != null and _voice.playing


func stop_voice() -> void:
	if _voice and _voice.playing:
		_voice.stop()
	_voice_duck(false)


## Music dips a little under speech.
func _voice_duck(on: bool) -> void:
	if "--no-music" in OS.get_cmdline_user_args():
		return
	_set_bus("Music", _music_vol * _duck * (0.55 if on else 1.0))


func _set_bus(name: String, lin: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.0001)))
		AudioServer.set_bus_mute(i, lin <= 0.001)


func stream(rel: String) -> AudioStream:
	if not _cache.has(rel):
		var path := DIR + rel
		_cache[rel] = load(path) if ResourceLoader.exists(path) else null
		if _cache[rel] is AudioStreamOggVorbis:
			(_cache[rel] as AudioStreamOggVorbis).loop = rel.begins_with("amb/")
	return _cache[rel]


# ------------------------------------------------------------------ music and ambience
func _fade(p: AudioStreamPlayer, to_db: float, t: float, stop_after := false) -> void:
	if _tw.has(p) and (_tw[p] as Tween).is_valid():
		(_tw[p] as Tween).kill()
	var tw := create_tween()
	var from := db_to_linear(p.volume_db)
	tw.tween_method(func(v: float): p.volume_db = linear_to_db(maxf(v, 0.0001)), from, db_to_linear(to_db), maxf(t, 0.01))
	if stop_after:
		tw.tween_callback(p.stop)
	_tw[p] = tw


func _cross(players: Array[AudioStreamPlayer], idx: int, rel: String, vol_db: float, t: float) -> int:
	var old := players[idx]
	var nxt := players[1 - idx]
	if old.playing:
		_fade(old, OFF_DB, t, true)
	var s := stream(rel)
	if s == null:
		return 1 - idx
	nxt.stream = s
	nxt.volume_db = OFF_DB
	nxt.play()
	_fade(nxt, vol_db, t)
	return 1 - idx


func _process(_delta: float) -> void:
	var p := _music[_mi]
	if p.playing:
		_maybe_loop(p.get_playback_position())


## Restart the current track on the other player when it is LOOP_XF seconds from its end.
func _maybe_loop(pos: float) -> bool:
	if _hold or music_name == "":
		return false
	var p := _music[_mi]
	if p.stream == null:
		return false
	var ln := p.stream.get_length()
	if ln <= LOOP_XF * 3.0 or pos < ln - LOOP_XF:
		return false
	_mi = _cross(_music, _mi, "music/%s.ogg" % music_name, MUSIC_DB.get(music_name, -4.0), LOOP_XF)
	return true


func play_music(name: String, t: float = FADE) -> void:
	if name == music_name:
		return
	music_name = name
	_mi = _cross(_music, _mi, "music/%s.ogg" % name, MUSIC_DB.get(name, -4.0), t)


func stop_music(t: float = FADE) -> void:
	music_name = ""
	for p in _music:
		if p.playing:
			_fade(p, OFF_DB, t, true)


func play_amb(name: String, t: float = FADE) -> void:
	if name == amb_name:
		return
	amb_name = name
	if name == "":
		for p in _amb:
			if p.playing:
				_fade(p, OFF_DB, t, true)
		return
	_ai = _cross(_amb, _ai, "amb/%s.ogg" % name, AMB_DB.get(name, 0.0), t)


## Indoors the music is muffled as if heard through the walls, and the ambience swaps to the room.
func set_indoor(on: bool, outdoor_amb: String = "day") -> void:
	indoor = on
	_room_reverb.wet=.10 if on else 0.0
	if _lp_tw and _lp_tw.is_valid():
		_lp_tw.kill()
	_lp_tw = create_tween()
	_lp_tw.tween_property(_lp, "cutoff_hz", 900.0 if on else 20000.0, 0.6)
	play_amb("room" if on else outdoor_amb, 0.8)


## One-shot cue on the music bus (the ending); the looping music dips underneath and returns.
func play_jingle(name: String) -> void:
	var s := stream("music/%s.ogg" % name)
	if s == null:
		return
	_jingle.stream = s
	_jingle.volume_db = MUSIC_DB.get(name, -2.0)
	_jingle.play()
	var dur := s.get_length()
	_hold = true
	for p in _music:
		if p.playing:
			_fade(p, OFF_DB, 1.2, true)
	var cur := music_name
	get_tree().create_timer(maxf(dur - 3.0, 1.0)).timeout.connect(func():
		_hold = false
		if music_name == cur and cur != "":
			music_name = ""
			play_music(cur, 3.0))


# ------------------------------------------------------------------ effects
func sfx(name: String, vol_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	var s := stream("sfx/%s.wav" % name)
	if s == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -10.0)) < 0.045:
		return
	_last[name] = now
	var p: AudioStreamPlayer = null
	for q in _pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _pool[0]
		_pool.push_back(_pool.pop_front())
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = bus
	p.play()


func ui(kind: String) -> void:
	sfx("ui_" + kind, {"hover": -6.0, "rotate": -4.0}.get(kind, -2.0), randf_range(0.98, 1.02), "UI")


func fx(kind: String, vol_db: float = -2.0) -> void:
	if game_on:
		sfx("fx_" + kind, vol_db, randf_range(0.97, 1.03))

## Physical interactions use their actual world position, with a bounded pool and range.
func fx_at(kind: String,at: Vector3,vol_db: float=-7.0) -> void:
	if not game_on or not at.is_finite():return
	var clip: String="%s_%d"%[kind,randi_range(0,3)] if kind in ["dish_place","cup_sip"] else kind
	var sample: AudioStream=stream("sfx/fx_%s.wav"%clip)
	if sample==null:return
	var listener: AudioListener3D=get_viewport().get_audio_listener_3d()
	if listener!=null and listener.global_position.distance_to(at)>18.0:return
	var source: AudioStreamPlayer3D=_world_pool[0]
	for candidate: AudioStreamPlayer3D in _world_pool:
		if not candidate.playing:source=candidate;break
	source.stop();source.global_position=at;source.stream=sample
	source.volume_db=vol_db;source.pitch_scale=randf_range(.97,1.03);source.play()


func sting(kind: String) -> void:
	if not game_on:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var rank: int = STING_RANK.get(kind, 0)
	if now < _sting_until and rank <= _sting_rank:
		return
	_sting_rank = rank
	var s := stream("sfx/sting_%s.wav" % kind)
	_sting_until = now + (minf(s.get_length(), 1.4) if s else 0.5)
	sfx("sting_" + kind, STING_DB.get(kind, -5.0))
	if rank >= 3:
		duck(0.45, 2.2)


## Dip the music under a big stinger.
func duck(to: float, hold: float) -> void:
	if _duck_tw and _duck_tw.is_valid():
		_duck_tw.kill()
	_duck_tw = create_tween()
	_duck_tw.tween_method(_set_duck, _duck, to, 0.15)
	_duck_tw.tween_interval(hold)
	_duck_tw.tween_method(_set_duck, to, 1.0, 1.2)


func _set_duck(v: float) -> void:
	_duck = v
	apply_volumes(GameState.settings)


func step_stream(surface: String) -> AudioStream:
	var s := surface if surface in SURFACES else "stone"
	return stream("sfx/step_%s_%d.wav" % [s, randi() % 4])


func footstep(surface: String, vol_db: float = -13.0) -> void:
	var s := surface if surface in SURFACES else "stone"
	sfx("step_%s_%d" % [s, randi() % 4], vol_db + {"wood": 1.0, "grass": -1.0, "tatami": -1.5}.get(s, 0.0), randf_range(0.93, 1.07))


# ------------------------------------------------------------------ automatic button sounds
func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		b.mouse_entered.connect(func():
			if not b.disabled:
				ui("hover"))
		b.pressed.connect(func(): ui("click"))
	elif n is HSlider:
		var sl := n as HSlider
		sl.value_changed.connect(func(_v): ui("hover"))


## Stop everything at once (before quitting, so no playback outlives the audio server).
func silence() -> void:
	for source: AudioStreamPlayer3D in _world_pool:source.stop();source.stream=null
	for t in _tw.values():
		if (t as Tween).is_valid():
			(t as Tween).kill()
	_tw.clear()
	for p in _music + _amb + _pool + [_jingle]:
		p.stop()
		p.stream = null
	music_name = ""
	amb_name = ""
	_hold = false


func _exit_tree() -> void:
	silence()
	_cache.clear()
