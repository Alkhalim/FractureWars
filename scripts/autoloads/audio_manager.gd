extends Node

# Volume settings
var sfx_volume: float = 0.7
var music_volume: float = 0.35

# Audio player pools
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _current_music: StringName = &""
var _music_tween: Tween = null  # Track active music tween to kill duplicates

# Pre-generated audio streams
var _sfx_cache: Dictionary = {} # sfx_name -> AudioStream

# Playlist system
var _playlists: Dictionary = {} # "faction:context" -> Array[AudioStream]
var _current_playlist_key: String = ""
var _current_playlist_index: int = 0

const SAMPLE_RATE := 22050
const MAX_SFX_PLAYERS := 6

static func _safe_linear_to_db(vol: float) -> float:
	if vol <= 0.0:
		return -80.0
	return linear_to_db(vol)

# Music file paths per faction and context
const MUSIC_FILES := {
	"empire": {
		"campaign": [
			"res://audio/music/marble_echoes.wav",
			"res://audio/music/imperial_buildup.wav",
		],
		"battle": [
			"res://audio/music/marching_sandals.wav",
			"res://audio/music/eagles_of_the_legion.wav",
		],
	},
	"skulloath": {
		"campaign": ["res://audio/music/horde_of_the_steppe.wav", "res://audio/music/hunnic_horde_rising.wav"],
		"battle": ["res://audio/music/breaking_sky.wav", "res://audio/music/riders_into_battle.wav"],
	},
}

# Thematic fallback: factions without own music use the closest-fitting faction's tracks
const MUSIC_FALLBACKS := {
	"gladehost": "empire",       # Noble forest elves — classical/noble
	"moonspear": "empire",       # Lunar elves — refined/celestial
	"sunblessed": "empire",      # Holy knights — imperial/noble
	"cinderguard": "empire",     # Frontier legion — marching/military
	"thunderswarm": "skulloath", # Storm barbarians — tribal/aggressive
	"forsaken": "skulloath",     # Vampire aristocrats — harsh/aggressive
	"ivoryscar": "skulloath",    # Desert relic-seekers — exotic/harsh
	"tainted_jade": "skulloath", # Jungle corruption — wild/primal
	"shardhorde": "skulloath",   # Crystal swarm — chaotic/alien
}

const SETTINGS_PATH := "user://audio_settings.cfg"

func _ready() -> void:
	# Load saved settings first
	_load_settings()

	# Create SFX player pool
	for i in MAX_SFX_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_sfx_players.append(player)

	# Create music player
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)

	# Pre-generate all placeholder SFX
	_generate_all_sfx()
	# Load music playlists
	_load_playlists()

	# Connect to game signals
	# Most gameplay sounds are handled by campaign.gd with LOS checks
	# Only connect non-positional sounds here
	EventBus.game_over.connect(func(_f, _v, is_player):
		if is_player:
			play_sfx(&"victory")
		else:
			play_sfx(&"defeat")
	)

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_save_settings()

func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_music_player.volume_db = _safe_linear_to_db(music_volume)
	_save_settings()

func play_sfx(sfx_name: StringName) -> void:
	var stream: AudioStream = _sfx_cache.get(sfx_name)
	if stream == null:
		return
	# Find an available player
	for player in _sfx_players:
		if not player.playing:
			player.stream = stream
			player.volume_db = _safe_linear_to_db(sfx_volume)
			player.play()
			return
	# All busy - use first one (interrupt oldest)
	_sfx_players[0].stream = stream
	_sfx_players[0].volume_db = _safe_linear_to_db(sfx_volume)
	_sfx_players[0].play()

func play_music(track_name: StringName) -> void:
	# For single-track playback (menu music)
	if track_name == _current_music and _music_player.playing:
		return
	_current_music = track_name
	_current_playlist_key = ""
	var stream: AudioStream = _sfx_cache.get(track_name)
	if stream == null:
		return
	_crossfade_to(stream)

func play_faction_music(faction_id: StringName, context: StringName) -> void:
	# context is &"campaign" or &"battle"
	var key := str(faction_id) + ":" + str(context)
	if key == _current_playlist_key and _music_player.playing:
		return
	_current_playlist_key = key
	_current_music = &""
	var playlist: Array = _playlists.get(key, [])
	# Fallback to thematically closest faction's music if none found
	if playlist.is_empty():
		var fallback_id: String = MUSIC_FALLBACKS.get(str(faction_id), "")
		if fallback_id != "":
			var fallback_key := fallback_id + ":" + str(context)
			playlist = _playlists.get(fallback_key, [])
	if playlist.is_empty():
		return
	_current_playlist_index = randi() % playlist.size()
	_crossfade_to(playlist[_current_playlist_index])

func _crossfade_to(stream: AudioStream) -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	if _music_player.playing and _music_player.volume_db > -20.0:
		# Currently audible — quick crossfade out, then switch
		_music_tween.tween_property(_music_player, "volume_db", -40.0, 0.8)
		_music_tween.tween_callback(func():
			_music_player.stream = stream
			_music_player.volume_db = -40.0
			_music_player.play()
		)
		_music_tween.tween_property(_music_player, "volume_db", _safe_linear_to_db(music_volume), 1.5)
	else:
		# Nothing playing or already faded — start immediately with fade-in
		_music_player.stop()
		_music_player.stream = stream
		_music_player.volume_db = -40.0
		_music_player.play()
		_music_tween.tween_property(_music_player, "volume_db", _safe_linear_to_db(music_volume), 1.5)

func _on_music_finished() -> void:
	# If playing a playlist, advance to next track
	if _current_playlist_key == "":
		# Single track (menu) — just loop
		_music_player.play()
		return
	var playlist: Array = _playlists.get(_current_playlist_key, [])
	if playlist.is_empty():
		return
	_current_playlist_index = (_current_playlist_index + 1) % playlist.size()
	_music_player.stream = playlist[_current_playlist_index]
	_music_player.volume_db = _safe_linear_to_db(music_volume)
	_music_player.play()

func stop_music() -> void:
	_current_music = &""
	_current_playlist_key = ""
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -40.0, 2.0)
	_music_tween.tween_callback(_music_player.stop)

# ── Playlist Loading ────────────────────────────────────────────

func _load_playlists() -> void:
	for faction_id in MUSIC_FILES:
		var faction_data: Dictionary = MUSIC_FILES[faction_id]
		for context in faction_data:
			var key: String = str(faction_id) + ":" + str(context)
			var tracks: Array = []
			var paths: Array = faction_data[context]
			for path in paths:
				var stream = load(str(path))
				if stream:
					tracks.append(stream)
			if not tracks.is_empty():
				_playlists[key] = tracks

# ── Programmatic Audio Generation ────────────────────────────

func _load_sfx_or_fallback(sfx_name: StringName, fallback: Callable) -> void:
	var path := "res://audio/sfx/%s.wav" % sfx_name
	if ResourceLoader.exists(path):
		var stream = load(path)
		if stream:
			_sfx_cache[sfx_name] = stream
			return
	_sfx_cache[sfx_name] = fallback.call()

func _generate_all_sfx() -> void:
	# Load real .wav files from res://audio/sfx/ with procedural fallback
	_load_sfx_or_fallback(&"ui_click", _gen_metallic_tap)
	_load_sfx_or_fallback(&"ui_click_alt", _gen_metallic_tap)  # Alt click variant
	_load_sfx_or_fallback(&"turn_chime", _gen_horn_fanfare)
	_load_sfx_or_fallback(&"battle_hit", _gen_metal_clash)
	_load_sfx_or_fallback(&"march", _gen_drum_beat)
	_load_sfx_or_fallback(&"shard_claim", _gen_crystal_chime)
	_load_sfx_or_fallback(&"build_complete", _gen_anvil_strike)
	_load_sfx_or_fallback(&"building_start", _gen_building_start)
	_load_sfx_or_fallback(&"recruit_start", _gen_recruit_trumpet)
	_load_sfx_or_fallback(&"victory", _gen_brass_fanfare)
	_load_sfx_or_fallback(&"defeat", _gen_horn_descent)
	_load_sfx_or_fallback(&"demolish", _gen_demolish)
	_load_sfx_or_fallback(&"gold_gain", _gen_crystal_chime)      # Coin sounds
	_load_sfx_or_fallback(&"scroll_open", _gen_building_start)    # Parchment sounds
	_load_sfx_or_fallback(&"door_close", _gen_demolish)           # Panel close
	# error_buzz: always procedural (no matching file)
	_sfx_cache[&"error_buzz"] = _gen_error_buzz()
	# Menu music (single track, not a playlist)
	var menu_music = load("res://audio/music/crown_of_ashes.wav")
	if menu_music:
		_sfx_cache[&"music_menu"] = menu_music
	else:
		_sfx_cache[&"music_menu"] = _gen_drone([120.0, 180.0, 240.0], 8.0)

# ── Utility: pseudo-random noise from seed ──────────────────────
# Deterministic hash-based noise so SFX are identical across runs.
func _noise(seed_val: int) -> float:
	# Simple integer hash → float in -1..1
	var h := ((seed_val * 1103515245 + 12345) >> 16) & 0x7FFF
	return float(h) / 16383.5 - 1.0

# ── Utility: sawtooth waveform (band-limited-ish via harmonics) ─
func _sawtooth(phase: float, harmonics: int = 8) -> float:
	var val := 0.0
	for k in range(1, harmonics + 1):
		val += sin(phase * float(k)) / float(k)
	return val * (2.0 / PI)

# ── Replaced SFX generators (medieval / fantasy) ────────────────

func _gen_metallic_tap() -> AudioStreamWAV:
	# ui_click – Metallic tap: 1200Hz + harmonics, noise transient, fast decay
	var duration := 0.07
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var env := maxf(0.0, 1.0 - t / duration)
		env *= env # quadratic decay for snappy feel
		# Noise transient in first 5 ms
		var noise_env := maxf(0.0, 1.0 - t / 0.005)
		var noise_val := _noise(i) * 0.35 * noise_env
		# Metallic ring: 1200 Hz fundamental + inharmonic overtones
		var ring := sin(t * 1200.0 * TAU) * 0.35
		ring += sin(t * 2640.0 * TAU) * 0.15 # ~2.2x (inharmonic)
		ring += sin(t * 4100.0 * TAU) * 0.08 # ~3.4x
		var val := (ring * env) + noise_val
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_horn_fanfare() -> AudioStreamWAV:
	# turn_chime – Horn fanfare: 220→330Hz sawtooth harmonics, 0.35s
	var duration := 0.35
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := t / duration
		# Pitch glide from 220 to 330 Hz (a musical fifth)
		var freq := lerpf(220.0, 330.0, minf(progress * 2.0, 1.0))
		# Brass-like envelope: quick attack, sustain, fade
		var env := minf(1.0, t / 0.02) * maxf(0.0, 1.0 - (progress - 0.7) / 0.3)
		env = clampf(env, 0.0, 1.0)
		var phase := t * freq * TAU
		var val := _sawtooth(phase, 6) * 0.45 * env
		# Add slight warmth with sub-octave
		val += sin(phase * 0.5) * 0.1 * env
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_metal_clash() -> AudioStreamWAV:
	# battle_hit – Metal clash: noise burst + inharmonic ring + low thud
	var duration := 0.2
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := t / duration
		# Noise burst: sharp 10ms transient
		var noise_env := maxf(0.0, 1.0 - t / 0.01)
		var noise_val := _noise(i) * 0.5 * noise_env
		# Inharmonic metallic ring (multiple non-integer-ratio frequencies)
		var ring_env := maxf(0.0, 1.0 - progress) * maxf(0.0, 1.0 - progress)
		var ring := sin(t * 1800.0 * TAU) * 0.2
		ring += sin(t * 2950.0 * TAU) * 0.12
		ring += sin(t * 4300.0 * TAU) * 0.07
		ring += sin(t * 780.0 * TAU) * 0.1
		ring *= ring_env
		# Low thud: 60 Hz sine, fast decay
		var thud_env := maxf(0.0, 1.0 - t / 0.08)
		var thud := sin(t * 60.0 * TAU) * 0.35 * thud_env
		var val := noise_val + ring + thud
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_drum_beat() -> AudioStreamWAV:
	# march – Drum beat: 80→50Hz pitch drop, noise transient
	var duration := 0.18
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := t / duration
		# Pitch drops quickly from 80 to 50 Hz
		var freq := lerpf(80.0, 50.0, minf(progress * 3.0, 1.0))
		var env := maxf(0.0, 1.0 - progress)
		env *= env
		# Drum body
		var body := sin(t * freq * TAU) * 0.55 * env
		# Noise transient (stick attack) — first 8ms
		var stick_env := maxf(0.0, 1.0 - t / 0.008)
		var stick := _noise(i) * 0.4 * stick_env
		var val := body + stick
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_crystal_chime() -> AudioStreamWAV:
	# shard_claim – Crystal chime: high harmonics with chorus detuning
	var duration := 0.4
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var env := minf(1.0, t / 0.005) * maxf(0.0, 1.0 - t / duration)
		# Base crystal tone at 2400 Hz
		var base_freq := 2400.0
		# Chorus: three slightly detuned copies
		var val := sin(t * base_freq * TAU) * 0.2
		val += sin(t * (base_freq + 7.0) * TAU) * 0.18 # +7 Hz detune
		val += sin(t * (base_freq - 5.0) * TAU) * 0.18 # -5 Hz detune
		# Higher harmonic shimmer
		val += sin(t * 3600.0 * TAU) * 0.1 * env
		val += sin(t * 4800.0 * TAU) * 0.06 * env
		val *= env
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_anvil_strike() -> AudioStreamWAV:
	# build_complete – Anvil strike: metallic ring with inharmonic partials
	var duration := 0.3
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := t / duration
		# Sharp attack
		var env := minf(1.0, t / 0.002) * maxf(0.0, 1.0 - progress)
		# Hammer impact noise
		var impact_env := maxf(0.0, 1.0 - t / 0.006)
		var impact := _noise(i) * 0.4 * impact_env
		# Inharmonic metallic partials (bell/anvil character)
		var ring := sin(t * 900.0 * TAU) * 0.2
		ring += sin(t * 1530.0 * TAU) * 0.15 # 1.7x
		ring += sin(t * 2340.0 * TAU) * 0.1 # 2.6x
		ring += sin(t * 3780.0 * TAU) * 0.06 # 4.2x
		ring += sin(t * 5400.0 * TAU) * 0.03 # 6.0x
		ring *= env
		var val := impact + ring
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_brass_fanfare() -> AudioStreamWAV:
	# victory – Brass fanfare: ascending 5th with sawtooth harmonics
	var duration := 0.6
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var switch_point := 0.3 # first note duration
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		# Two notes: root then a perfect 5th above
		var freq: float
		var note_t: float
		if t < switch_point:
			freq = 330.0 # E4
			note_t = t
		else:
			freq = 495.0 # B4 (perfect 5th)
			note_t = t - switch_point
		# Brass envelope per note
		var note_dur := switch_point if t < switch_point else (duration - switch_point)
		var env := minf(1.0, note_t / 0.015) * maxf(0.0, 1.0 - (note_t - note_dur + 0.05) / 0.05)
		env = clampf(env, 0.0, 1.0)
		var phase := t * freq * TAU
		var val := _sawtooth(phase, 8) * 0.35 * env
		# Add octave below for fullness
		val += sin(phase * 0.5) * 0.12 * env
		# Slight chorus
		val += sin(phase * 1.002) * 0.08 * env
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_horn_descent() -> AudioStreamWAV:
	# defeat – Low horn descent with rumble undertone
	var duration := 0.55
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := t / duration
		# Descending horn: 220 → 130 Hz
		var freq := lerpf(220.0, 130.0, progress)
		var env := minf(1.0, t / 0.03) * maxf(0.0, 1.0 - progress * 0.9)
		var phase := t * freq * TAU
		var val := _sawtooth(phase, 5) * 0.35 * env
		# Sub-bass rumble
		var rumble := sin(t * 40.0 * TAU) * 0.2 * env
		# Slight noise undertone for grit
		var grit := _noise(i) * 0.06 * env
		val += rumble + grit
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

# ── New SFX generators ──────────────────────────────────────────

func _gen_error_buzz() -> AudioStreamWAV:
	# error_buzz – Low dissonant beating (180Hz + 195Hz), 0.15s
	var duration := 0.15
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var env := minf(1.0, t / 0.005) * maxf(0.0, 1.0 - t / duration)
		# Two close frequencies create a dissonant beating pattern
		var val := sin(t * 180.0 * TAU) * 0.35
		val += sin(t * 195.0 * TAU) * 0.35
		# Add slight grit
		val += _noise(i) * 0.05 * env
		val *= env
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_building_start() -> AudioStreamWAV:
	# building_start – Two hammer-on-stone taps (400Hz resonance + noise)
	var duration := 0.25
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	# Two taps at t=0 and t=0.12
	var tap_times: Array[float] = [0.0, 0.12]
	var tap_dur := 0.08
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var val := 0.0
		for tap_start in tap_times:
			var dt := t - tap_start
			if dt >= 0.0 and dt < tap_dur:
				var tap_env := maxf(0.0, 1.0 - dt / tap_dur)
				tap_env *= tap_env
				# Stone resonance at 400 Hz
				val += sin(dt * 400.0 * TAU) * 0.25 * tap_env
				# Higher partial for brightness
				val += sin(dt * 920.0 * TAU) * 0.1 * tap_env
				# Impact noise
				var noise_env := maxf(0.0, 1.0 - dt / 0.006)
				val += _noise(i + int(tap_start * 10000.0)) * 0.3 * noise_env
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_recruit_trumpet() -> AudioStreamWAV:
	# recruit_start – Brief trumpet call (ascending 300→450Hz brass)
	var duration := 0.25
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := t / duration
		# Quick ascending pitch
		var freq := lerpf(300.0, 450.0, minf(progress * 2.5, 1.0))
		# Trumpet envelope
		var env := minf(1.0, t / 0.01) * maxf(0.0, 1.0 - (progress - 0.6) / 0.4)
		env = clampf(env, 0.0, 1.0)
		var phase := t * freq * TAU
		var val := _sawtooth(phase, 6) * 0.38 * env
		# Brightness partial
		val += sin(phase * 2.0) * 0.1 * env
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_demolish() -> AudioStreamWAV:
	# demolish – Crumbling: descending rumble + noise, 0.3s
	var duration := 0.3
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := t / duration
		var env := minf(1.0, t / 0.01) * maxf(0.0, 1.0 - progress * 0.8)
		# Descending rumble: 120 → 40 Hz
		var freq := lerpf(120.0, 40.0, progress)
		var rumble := sin(t * freq * TAU) * 0.3 * env
		# Crumbling noise — increases then fades
		var noise_env := sin(progress * PI) # peaks in the middle
		var crumble := _noise(i) * 0.35 * noise_env * env
		# Some mid-range debris impacts
		var debris := sin(t * 250.0 * TAU) * 0.1 * env * maxf(0.0, 1.0 - progress * 2.0)
		var val := rumble + crumble + debris
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

# ── Shared generators (kept for menu music fallback) ────────────

func _gen_drone(freqs: Array, duration: float) -> AudioStreamWAV:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var amp := 0.15 / float(freqs.size())
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		# Fade in/out for seamless looping
		var envelope := minf(1.0, t * 2.0) * minf(1.0, (duration - t) * 2.0)
		var val := 0.0
		for j in freqs.size():
			var freq: float = freqs[j]
			# Slight detuning for richness
			var detune := sin(t * 0.3 * float(j + 1)) * 2.0
			val += sin(t * (freq + detune) * TAU) * amp
		val *= envelope
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var wav := _make_wav(data, samples)
	# No loop — _on_music_finished handles replay to avoid Godot 4.6 infinite loop detection
	return wav

func _make_wav(data: PackedByteArray, sample_count: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav

# ── Settings Persistence ───────────────────────────────────────

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_volume = cfg.get_value("audio", "music_volume", 0.35)
		sfx_volume = cfg.get_value("audio", "sfx_volume", 0.7)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.save(SETTINGS_PATH)

# ── Options Panel Factory ──────────────────────────────────────

func create_options_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "OptionsPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.18, 0.95)
	style.border_color = Color(0.55, 0.42, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.size = Vector2(380, 480)
	panel.position = (parent.get_viewport_rect().size - panel.size) / 2.0
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Music volume slider
	_add_volume_row(vbox, "Music Volume", music_volume, func(val: float):
		set_music_volume(val)
	)

	# SFX volume slider
	_add_volume_row(vbox, "SFX Volume", sfx_volume, func(val: float):
		set_sfx_volume(val)
		play_sfx(&"ui_click")
	)

	# --- Graphics Settings ---
	var gfx_title := Label.new()
	gfx_title.text = "GRAPHICS"
	gfx_title.add_theme_font_size_override("font_size", 14)
	gfx_title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	gfx_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gfx_title)

	# Fullscreen toggle
	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 10)
	vbox.add_child(fs_row)
	var fs_label := Label.new()
	fs_label.text = "Fullscreen"
	fs_label.custom_minimum_size = Vector2(120, 0)
	fs_label.add_theme_font_size_override("font_size", 13)
	fs_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	fs_row.add_child(fs_label)
	var fs_check := CheckButton.new()
	fs_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs_check.toggled.connect(func(on: bool):
		if on:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_save_settings()
	)
	fs_row.add_child(fs_check)

	# UI Scale slider
	_add_volume_row(vbox, "UI Scale", get_tree().root.content_scale_factor, func(val: float):
		get_tree().root.content_scale_factor = lerpf(1.0, 1.5, val)
		_save_settings()
	)

	# Screen Shake toggle
	var shake_row := HBoxContainer.new()
	shake_row.add_theme_constant_override("separation", 10)
	vbox.add_child(shake_row)
	var shake_label := Label.new()
	shake_label.text = "Screen Shake"
	shake_label.custom_minimum_size = Vector2(120, 0)
	shake_label.add_theme_font_size_override("font_size", 13)
	shake_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	shake_row.add_child(shake_label)
	var shake_check := CheckButton.new()
	shake_check.button_pressed = not GameManager.has_meta("disable_screen_shake")
	shake_check.toggled.connect(func(on: bool):
		if on:
			GameManager.remove_meta("disable_screen_shake")
		else:
			GameManager.set_meta("disable_screen_shake", true)
	)
	shake_row.add_child(shake_check)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 32)
	close_btn.pressed.connect(func():
		play_sfx(&"ui_click")
		panel.queue_free()
	)
	vbox.add_child(close_btn)

	return panel

func _add_volume_row(parent: VBoxContainer, label_text: String, initial_value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(140, 0)
	row.add_child(slider)

	var pct_label := Label.new()
	pct_label.text = "%d%%" % int(initial_value * 100)
	pct_label.custom_minimum_size = Vector2(40, 0)
	pct_label.add_theme_font_size_override("font_size", 12)
	pct_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	row.add_child(pct_label)

	slider.value_changed.connect(func(val: float):
		pct_label.text = "%d%%" % int(val * 100)
		on_change.call(val)
	)
