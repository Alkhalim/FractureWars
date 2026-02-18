extends Node

# Volume settings
var sfx_volume: float = 0.7
var music_volume: float = 0.5

# Audio player pools
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _current_music: StringName = &""

# Pre-generated audio streams
var _sfx_cache: Dictionary = {} # sfx_name -> AudioStream

const SAMPLE_RATE := 22050
const MAX_SFX_PLAYERS := 6

func _ready() -> void:
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

	# Pre-generate all placeholder SFX
	_generate_all_sfx()

	# Connect to game signals
	EventBus.army_moved.connect(func(_a, _b, _c): play_sfx(&"march"))
	EventBus.battle_resolved.connect(func(_a, _b): play_sfx(&"battle_hit"))
	EventBus.building_completed.connect(func(_a, _b): play_sfx(&"build_complete"))
	EventBus.shardfall_occurred.connect(func(_a, _b, _c): play_sfx(&"shard_claim"))
	EventBus.turn_started.connect(func(_t, _f): play_sfx(&"turn_chime"))
	EventBus.game_over.connect(func(_f, _v, is_player):
		if is_player:
			play_sfx(&"victory")
		else:
			play_sfx(&"defeat")
	)

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)

func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_music_player.volume_db = linear_to_db(music_volume)

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
	if track_name == _current_music and _music_player.playing:
		return
	_current_music = track_name
	var stream: AudioStream = _sfx_cache.get(track_name)
	if stream == null:
		return
	# Crossfade: fade out then start new
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -40.0, 0.5)
	tween.tween_callback(func():
		_music_player.stream = stream
		_music_player.volume_db = linear_to_db(music_volume)
		_music_player.play()
	)

func stop_music() -> void:
	_current_music = &""
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -40.0, 0.5)
	tween.tween_callback(_music_player.stop)

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
	# Ambient music drones
	_sfx_cache[&"music_menu"] = _gen_drone([120.0, 180.0, 240.0], 8.0)
	_sfx_cache[&"music_campaign"] = _gen_drone([100.0, 150.0, 200.0, 300.0], 8.0)
	_sfx_cache[&"music_battle"] = _gen_drone([80.0, 160.0, 240.0, 320.0], 6.0)

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
		var freq := freq1 if i < switch_sample else freq2
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
