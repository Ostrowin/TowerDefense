class_name Sfx
extends Node
## Efekty dźwiękowe i muzyka syntezowane w kodzie — zero plików audio.
## Każdy efekt ma limit częstotliwości odtwarzania, żeby 30 strzał naraz
## nie zlało się w jeden szum. Efekty grają na szynie „SFX", muzyka na „Music"
## (głośności: Settings). Pętla muzyczna liczy się w tle, w wątku roboczym.

const RATE := 22050
const MUSIC_RATE := 16000
const VOICES := 12

var muted := false:
	set(value):
		muted = value
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), value)
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _music: AudioStreamPlayer
var _music_task := -1


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -8.0
	add_child(_music)
	_music_task = WorkerThreadPool.add_task(func() -> void:
		var stream := make_music()
		_start_music.call_deferred(stream))

	_streams["arrow"] = _synth(0.05, func(t: float) -> float: return _square(_sweep(t, 1400, 800, 0.05)) * 0.12)
	_streams["cannonball"] = _synth(0.3, func(t: float) -> float:
		return (randf_range(-1, 1) * 0.5 + sin(_sweep(t, 110, 40, 0.3)) * 0.8) * exp(-t * 12.0))
	_streams["rock"] = _synth(0.25, func(t: float) -> float:
		return (randf_range(-1, 1) * 0.3 + sin(_sweep(t, 180, 70, 0.25)) * 0.5) * exp(-t * 10.0))
	_streams["hit"] = _synth(0.04, func(_t: float) -> float: return randf_range(-1, 1) * 0.18)
	_streams["explosion"] = _synth(0.45, func(t: float) -> float:
		return (randf_range(-1, 1) * 0.7 + sin(TAU * 55.0 * t) * 0.5) * exp(-t * 7.0))
	_streams["death"] = _synth(0.14, func(t: float) -> float: return _square(_sweep(t, 520, 140, 0.14)) * 0.14)
	_streams["build"] = _synth(0.16, func(t: float) -> float:
		return sin(TAU * (523.0 if t < 0.07 else 784.0) * t) * 0.35)
	_streams["upgrade"] = _synth(0.3, func(t: float) -> float:
		return sin(TAU * _arp(t, 0.1, [523.0, 659.0, 784.0]) * t) * 0.35)
	_streams["sell"] = _synth(0.18, func(t: float) -> float:
		return sin(TAU * (784.0 if t < 0.08 else 523.0) * t) * 0.3)
	_streams["coin"] = _synth(0.1, func(t: float) -> float:
		return _square(TAU * (1320.0 if t < 0.04 else 1760.0) * t) * 0.08)
	_streams["error"] = _synth(0.14, func(t: float) -> float: return _square(TAU * 150.0 * t) * 0.15)
	_streams["alarm"] = _synth(0.3, func(t: float) -> float:
		return _square(TAU * (880.0 if fmod(t, 0.1) < 0.05 else 660.0) * t) * 0.1)
	_streams["click"] = _synth(0.03, func(t: float) -> float: return sin(TAU * 900.0 * t) * 0.25)
	_streams["frost"] = _synth(0.22, func(t: float) -> float:
		return (sin(_sweep(t, 2200, 1300, 0.22)) * 0.6 + randf_range(-1, 1) * 0.15) * exp(-t * 9.0) * 0.25)
	_streams["volley"] = _synth(0.35, func(t: float) -> float:
		return randf_range(-1, 1) * (0.5 + 0.5 * sin(TAU * 40.0 * t)) * exp(-t * 6.0) * 0.35)
	_streams["levy"] = _synth(0.5, func(t: float) -> float: return _horn(t, 330.0 if t < 0.2 else 440.0) * 0.35)
	_streams["repair"] = _synth(0.4, func(t: float) -> float:
		return sin(TAU * _arp(t, 0.08, [523.0, 659.0, 784.0, 1047.0]) * t) * exp(-t * 3.0) * 0.35)
	_streams["base_hit"] = _synth(0.3, func(t: float) -> float:
		return (sin(_sweep(t, 140, 45, 0.3)) * 0.8 + randf_range(-1, 1) * 0.2) * exp(-t * 8.0))
	_streams["wave"] = _synth(0.7, func(t: float) -> float: return _horn(t, 220.0) * 0.35)
	_streams["boss"] = _synth(1.3, func(t: float) -> float: return _horn(t, 110.0) * 0.5)
	_streams["win"] = _synth(1.0, func(t: float) -> float:
		return sin(TAU * _arp(t, 0.16, [523.0, 659.0, 784.0, 1047.0]) * t) * 0.35)
	_streams["lose"] = _synth(1.1, func(t: float) -> float:
		return _square(TAU * _arp(t, 0.22, [392.0, 330.0, 262.0, 196.0]) * t) * 0.12)


func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1


func _start_music(stream: AudioStreamWAV) -> void:
	if not is_inside_tree():
		return
	_music.stream = stream
	_music.play()


func play(sound: String, min_gap := 0.05) -> void:
	if muted or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_played.get(sound, -INF) < min_gap:
		return
	_last_played[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


# ---------------------------------------------------------------- synteza

## Próbkuje fn(t) przez `duration` s do 16-bitowego PCM. Krótki fade in/out
## na brzegach usuwa trzaski.
func _synth(duration: float, fn: Callable) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var edge := minf(1.0, minf(t / 0.004, (duration - t) / 0.02))
		var v: float = fn.call(t) * edge
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## Spokojna pętla w a-moll: Am–F–C–G po takcie, 96 BPM, ~10 s.
##
##   bas      — pryma akordu co ćwierćnutę, szarpnięta (szybkie wybrzmienie)
##   arpeggio — ósemki po dźwiękach akordu, fala trójkątna, dwie oktawy wyżej
##   pad      — akord oktawę wyżej, ciche sinusy z płynnym wejściem i wyjściem
static func make_music() -> AudioStreamWAV:
	var beat := 60.0 / 96.0
	var bar := beat * 4.0
	var eighth := beat / 2.0
	var chords := [[110.0, 130.81, 164.81], [87.31, 110.0, 130.81], [130.81, 164.81, 196.0], [98.0, 123.47, 146.83]]
	var arp_order := [0, 1, 2, 1]
	var n := int(bar * chords.size() * MUSIC_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MUSIC_RATE
		var ch: Array = chords[int(t / bar) % chords.size()]
		var tb := fmod(t, bar)
		var tq := fmod(t, beat)
		var bass := sin(TAU * ch[0] * t) * exp(-tq * 3.0) * minf(1.0, tq / 0.005) * 0.45
		var k := int(tb / eighth)
		var te := fmod(tb, eighth)
		var f: float = ch[arp_order[k % 4]] * 4.0
		var arp := (1.0 - 4.0 * absf(fposmod(f * t, 1.0) - 0.5)) * exp(-te * 6.0) * minf(1.0, te / 0.005) * 0.16
		var pad_env := minf(1.0, tb / 0.4) * minf(1.0, (bar - tb) / 0.4)
		var pad := (sin(TAU * ch[0] * 2.0 * t) + sin(TAU * ch[1] * 2.0 * t) + sin(TAU * ch[2] * 2.0 * t)) * 0.05 * pad_env
		data.encode_s16(i * 2, int(clampf((bass + arp + pad) * 0.7, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MUSIC_RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s


## Faza (w radianach) tonu przesuwanego liniowo od f0 do f1 w czasie `dur`.
static func _sweep(t: float, f0: float, f1: float, dur: float) -> float:
	return TAU * (f0 * t + (f1 - f0) * t * t / (2.0 * dur))


static func _square(phase: float) -> float:
	return 1.0 if sin(phase) >= 0.0 else -1.0


static func _arp(t: float, step: float, notes: Array) -> float:
	return notes[mini(int(t / step), notes.size() - 1)]


static func _horn(t: float, f: float) -> float:
	var vib := 1.0 + 0.01 * sin(TAU * 5.0 * t)
	var ph := TAU * f * vib * t
	return (sin(ph) + 0.4 * sin(2.0 * ph) + 0.2 * sin(3.0 * ph)) * minf(1.0, t * 8.0) * exp(-t * 1.2)
