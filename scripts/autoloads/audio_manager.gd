extends Node

# Volume settings
var sfx_volume: float = 0.7
var music_volume: float = 0.35

# Audio player pools
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _current_music: StringName = &""

# Pre-generated audio streams
var _sfx_cache: Dictionary = {} # sfx_name -> AudioStream

# Playlist system
var _playlists: Dictionary = {} # "faction:context" -> Array[AudioStream]
var _current_playlist_key: String = ""
var _current_playlist_index: int = 0

const SAMPLE_RATE := 22050
const MAX_SFX_PLAYERS := 6

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
	# Placeholders — use Empire music until faction-specific tracks are added
	"skulloath": {
		"campaign": ["res://audio/music/horde_of_the_steppe.wav", "res://audio/music/hunnic_horde_rising.wav"],
		"battle": ["res://audio/music/breaking_sky.wav", "res://audio/music/riders_into_battle.wav"],
	},
	"gladehost": {
		"campaign": ["res://audio/music/marble_echoes.wav", "res://audio/music/imperial_buildup.wav"],
		"battle": ["res://audio/music/marching_sandals.wav", "res://audio/music/eagles_of_the_legion.wav"],
	},
	"tainted_jade": {
		"campaign": ["res://audio/music/marble_echoes.wav", "res://audio/music/imperial_buildup.wav"],
		"battle": ["res://audio/music/marching_sandals.wav", "res://audio/music/eagles_of_the_legion.wav"],
	},
	"shardhorde": {
		"campaign": ["res://audio/music/marble_echoes.wav", "res://audio/music/imperial_buildup.wav"],
		"battle": ["res://audio/music/marching_sandals.wav", "res://audio/music/eagles_of_the_legion.wav"],
	},
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
	_music_player.volume_db = linear_to_db(music_volume)
	_save_settings()

func play_sfx(sfx_name: StringName) -> void:
	var stream: AudioStream = _sfx_cache.get(sfx_name)
	if stream == null:
		return
	# Find an available player
	for player in _sfx_players:
		if not player.playing:
			player.stream = stream
			player.volume_db = linear_to_db(sfx_volume)
			player.play()
			return
	# All busy - use first one (interrupt oldest)
	_sfx_players[0].stream = stream
	_sfx_players[0].volume_db = linear_to_db(sfx_volume)
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
	if playlist.is_empty():
		return
	_current_playlist_index = randi() % playlist.size()
	_crossfade_to(playlist[_current_playlist_index])

func _crossfade_to(stream: AudioStream) -> void:
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -40.0, 2.0)
	tween.tween_callback(func():
		_music_player.stream = stream
		_music_player.volume_db = -40.0
		_music_player.play()
	)
	tween.tween_property(_music_player, "volume_db", linear_to_db(music_volume), 1.5)

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
	_music_player.volume_db = linear_to_db(music_volume)
	_music_player.play()

func stop_music() -> void:
	_current_music = &""
	_current_playlist_key = ""
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -40.0, 2.0)
	tween.tween_callback(_music_player.stop)

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

func _generate_all_sfx() -> void:
	_sfx_cache[&"ui_click"] = _gen_tone(800.0, 0.05, 0.8)
	_sfx_cache[&"turn_chime"] = _gen_two_tone(400.0, 600.0, 0.1, 0.1)
	_sfx_cache[&"battle_hit"] = _gen_tone(120.0, 0.1, 0.9, true)
	_sfx_cache[&"march"] = _gen_march(300.0, 0.15)
	_sfx_cache[&"shard_claim"] = _gen_shimmer(1200.0, 0.3)
	_sfx_cache[&"build_complete"] = _gen_tone(250.0, 0.08, 0.7)
	_sfx_cache[&"victory"] = _gen_chord([400.0, 500.0, 600.0], 0.5)
	_sfx_cache[&"defeat"] = _gen_descend(500.0, 200.0, 0.4)
	# Menu music (single track, not a playlist)
	var menu_music = load("res://audio/music/crown_of_ashes.wav")
	if menu_music:
		_sfx_cache[&"music_menu"] = menu_music
	else:
		_sfx_cache[&"music_menu"] = _gen_drone([120.0, 180.0, 240.0], 8.0)

func _gen_tone(freq: float, duration: float, amp: float = 0.5, decay: bool = false) -> AudioStreamWAV:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var envelope := 1.0
		if decay:
			envelope = maxf(0.0, 1.0 - t / duration)
		var val := sin(t * freq * TAU) * amp * envelope
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_two_tone(freq1: float, freq2: float, dur1: float, dur2: float) -> AudioStreamWAV:
	var total_samples := int(SAMPLE_RATE * (dur1 + dur2))
	var data := PackedByteArray()
	data.resize(total_samples * 2)
	var switch_sample := int(SAMPLE_RATE * dur1)
	for i in total_samples:
		var t := float(i) / float(SAMPLE_RATE)
		var freq: float = freq1 if i < switch_sample else freq2
		var val := sin(t * freq * TAU) * 0.5
		# Fade out at end
		var remaining := float(total_samples - i) / float(SAMPLE_RATE)
		if remaining < 0.03:
			val *= remaining / 0.03
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, total_samples)

func _gen_march(freq: float, duration: float) -> AudioStreamWAV:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		# Pulse pattern: two quick beats
		var pulse := 0.0
		var beat_pos := fmod(t * 6.0, 1.0)
		if beat_pos < 0.15:
			pulse = sin(t * freq * TAU) * 0.6 * (1.0 - beat_pos / 0.15)
		var sample := clampi(int(pulse * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_shimmer(freq: float, duration: float) -> AudioStreamWAV:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var vibrato := sin(t * 8.0 * TAU) * 50.0
		var envelope := maxf(0.0, 1.0 - t / duration)
		var val := sin(t * (freq + vibrato) * TAU) * 0.4 * envelope
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_chord(freqs: Array, duration: float) -> AudioStreamWAV:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var amp := 0.3 / float(freqs.size())
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var envelope := minf(1.0, t * 20.0) * maxf(0.0, 1.0 - t / duration)
		var val := 0.0
		for freq in freqs:
			val += sin(t * freq * TAU) * amp
		val *= envelope
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

func _gen_descend(freq_start: float, freq_end: float, duration: float) -> AudioStreamWAV:
	var samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(SAMPLE_RATE)
		var progress := t / duration
		var freq := lerpf(freq_start, freq_end, progress)
		var envelope := maxf(0.0, 1.0 - progress * 0.8)
		var val := sin(t * freq * TAU) * 0.5 * envelope
		var sample := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return _make_wav(data, samples)

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
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples
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
	panel.size = Vector2(380, 280)
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
