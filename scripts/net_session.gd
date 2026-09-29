class_name NetSession
extends RefCounted
## Gra sieciowa w lockstepie (multiplayer T4, docs/designs/multiplayer.md): ENet w Wi-Fi, topologia gwiazdy.
## Host zbiera komendy wszystkich graczy na krok N i rozsyła je każdemu jako „turę N”; krok N rusza dopiero,
## gdy tura N jest znana — przy braku gra czeka (nigdy nie porzuca kroków). Komenda wydana w kroku S idzie
## na turę S + DELAY. Każdy telefon wysyła swoją paczkę na każdą turę (także pustą), więc tura się zamyka.
## Host wpisuje numer gracza z połączenia (R5) — pole `player` z pakietu nie ma znaczenia. Co CHECK_EVERY
## kroków suma kontrolna Sim (`Sim.checksum`) — różna u kogokolwiek = rozjazd, koniec partii z raportem.
## Zerwanie połączenia = koniec partii. Bez węzłów: właściciel woła `poll()` i `try_step()` co klatkę.
##
## Pakiety (`var_to_bytes` tablic prostych wartości, bez obiektów):
##   gość → host: ["in", tura, [komendy]] · ["sum", krok, suma] · ["pick", dowódca] (lobby)
##   oba: ["pause", bool] (host rozsyła dalej)
##   host → gość: ["hello", gracz] · ["start", [gracze], ustawienia] · ["turn", tura, [komendy]] · ["end", powód]

signal ended(reason: String)
signal paused(on: bool)

const PORT := 24650
const DELAY := 3  ## opóźnienie wejścia w krokach (100 ms)
const CHECK_EVERY := 30
const STEP := 1.0 / 30.0
const TIMEOUT_MS := 5000  ## brak odzewu tak długo = zerwane połączenie

var sim: Sim
var is_host := false
var me := 0  ## mój gracz (host = 0, goście dostają numer od hosta)
var players: Array[int] = []  ## gracze w grze (host: znani od razu; gość: z pakietu start)
var started := false
var over := ""  ## powód końca ("" = trwa)
var step := 0  ## następny krok do wykonania
var peer: ENetMultiplayerPeer
var pending: Array[Dictionary] = []  ## moje komendy czekające na najbliższą paczkę
var desync_step := -1
var picks := {}  ## host: gracz → wybrany dowódca (lobby)
var start_cfg := {}  ## ustawienia partii od hosta (lobby → `Main.start_net`)

var _turns := {}  ## tura → [komendy] (gotowe do wykonania)
var _inputs := {}  ## host: tura → {gracz: [komendy]}
var _sums := {}  ## host: krok → {gracz: suma}
var _peer_player := {}  ## host: id połączenia ENet → gracz
var _sent_upto := DELAY - 1  ## ostatnia tura, na którą wysłałem paczkę


## Host: nasłuchuje na `port`, przyjmuje do `max_guests` gości.
func host(port := PORT, max_guests := 1) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_guests)
	if err != OK:
		return err
	is_host = true
	me = 0
	players = [0]
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_guest_left)
	return OK


## Host: gość odszedł — w trakcie partii koniec, w lobby tylko zwalnia miejsce.
func _on_guest_left(id: int) -> void:
	if started:
		_end("Połączenie przerwane")
	elif _peer_player.has(id):
		var p: int = _peer_player[id]
		_peer_player.erase(id)
		players.erase(p)
		picks.erase(p)


func join(ip: String, port := PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	is_host = false
	peer.peer_disconnected.connect(func(_id: int) -> void: _end("Połączenie przerwane"))
	return OK


## Host: liczba podłączonych gości (lobby czeka na komplet przed `start`).
func guest_count() -> int:
	return _peer_player.size()


## Host: start partii — `sim` musi już mieć wszystkich graczy (`players`); `cfg` idzie do gości (z niego
## budują ten sam Sim — `Main.start_net`).
func start(sim_: Sim, cfg := {}) -> void:
	sim = sim_
	if is_host:
		started = true
		start_cfg = cfg
		_broadcast(["start", players, cfg])


## Pauza u wszystkich — poza turami (w pauzie kroki stoją, więc tura ze wznowieniem by nie doszła).
## Lockstep i tak trzyma oba telefony w tym samym kroku; pauza to tylko wspólny ekran.
func send_pause(on: bool) -> void:
	if is_host:
		_broadcast(["pause", on])
		paused.emit(on)
	else:
		_send_host(["pause", on])


## Gość: wybór dowódcy w lobby (host zbiera w `picks`).
func send_pick(commander: String) -> void:
	_send_host(["pick", commander])


## Gość: Sim dostaje po pakiecie „start” (lobby tworzy go z tych samych ustawień).
func attach(sim_: Sim) -> void:
	sim = sim_


## Moja komenda (z widoku) — pójdzie na turę bieżący krok + DELAY.
func send(cmd: Dictionary) -> void:
	cmd["player"] = me
	pending.append(cmd)


func close() -> void:
	if peer != null:
		peer.close()
		peer = null


## Odbiór pakietów — co klatkę, także przed startem (lobby).
func poll() -> void:
	if peer == null:
		return
	peer.poll()
	if not is_host and started and peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_end("Połączenie przerwane")
	while peer != null and peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var msg: Variant = bytes_to_var(peer.get_packet())
		if msg is Array and not msg.is_empty():
			_receive(from, msg)


## Wykonuje jeden krok, jeśli tura jest znana. false = czekamy (albo koniec).
func try_step() -> bool:
	if not started or over != "" or sim == null:
		return false
	if step >= DELAY and not _turns.has(step):
		return false
	_send_input(step + DELAY)
	var cmds: Array = _turns.get(step, [])
	_turns.erase(step)
	for cmd: Variant in cmds:
		if cmd is Dictionary:
			sim.apply(cmd)
	sim.step(STEP)
	step += 1
	if step % CHECK_EVERY == 0:
		var sum := sim.checksum()
		if is_host:
			_add_sum(step, me, sum)
		else:
			_send_host(["sum", step, sum])
	return true


# ---------------------------------------------------------------- wewnętrzne

func _on_connected(id: int) -> void:
	if started:
		return  # v1: bez dołączania w trakcie
	var p := 2  # najmniejszy wolny numer — Sim nadaje graczy coop kolejno od 2 (`add_player`)
	while players.has(p):
		p += 1
	_peer_player[id] = p
	players.append(p)
	_send_to(id, ["hello", p])
	_set_timeout(peer.get_peer(id))


func _set_timeout(pp: ENetPacketPeer) -> void:
	if pp != null:
		pp.set_timeout(0, TIMEOUT_MS / 2, TIMEOUT_MS)


func _receive(from: int, msg: Array) -> void:
	match msg[0]:
		"hello":  # gość
			if msg.size() == 2 and msg[1] is int:
				me = msg[1]
				_set_timeout(peer.get_peer(1))
		"start":
			if msg.size() >= 2 and msg[1] is Array:
				players.assign(msg[1])
				if msg.size() > 2 and msg[2] is Dictionary:
					start_cfg = msg[2]
				started = true
		"pick":
			if is_host and not started and _peer_player.has(from) and msg.size() == 2 and msg[1] is String 					and Cfg.COMMANDERS.has(msg[1]) and Cfg.commander_ready(msg[1]):
				picks[_peer_player[from]] = msg[1]
		"turn":
			if msg.size() == 3 and msg[1] is int and msg[2] is Array:
				_turns[msg[1]] = msg[2]
		"pause":
			if msg.size() == 2 and msg[1] is bool:
				if is_host:
					_broadcast(["pause", msg[1]])
				paused.emit(msg[1])
		"end":
			_end(str(msg[1]) if msg.size() > 1 else "Koniec", false)
		"in":  # host: paczka gościa na turę
			if is_host and _peer_player.has(from) and msg.size() == 3 and msg[1] is int and msg[2] is Array:
				_add_input(msg[1], _peer_player[from], msg[2])
		"sum":
			if is_host and _peer_player.has(from) and msg.size() == 3 and msg[1] is int and msg[2] is int:
				_add_sum(msg[1], _peer_player[from], msg[2])


## Moja paczka na turę `turn` (raz na turę).
func _send_input(turn: int) -> void:
	if turn <= _sent_upto:
		return
	_sent_upto = turn
	var cmds := pending.duplicate()
	pending.clear()
	if is_host:
		_add_input(turn, me, cmds)
	else:
		_send_host(["in", turn, cmds])


## Host: paczka gracza `player` na turę; gdy są od wszystkich — tura gotowa, rozsyła ją.
## Numer gracza w komendach zawsze z połączenia (R5), kolejność: po graczu, potem po kolejności wysłania.
func _add_input(turn: int, player: int, cmds: Array) -> void:
	var got: Dictionary = _inputs.get(turn, {})
	var own: Array = []
	for cmd: Variant in cmds:
		if cmd is Dictionary:
			var c: Dictionary = cmd
			c["player"] = player
			own.append(c)
	got[player] = own
	_inputs[turn] = got
	if got.size() < players.size():
		return
	var all: Array = []
	var ids := players.duplicate()
	ids.sort()
	for p: int in ids:
		all.append_array(got[p])
	_inputs.erase(turn)
	_turns[turn] = all
	_broadcast(["turn", turn, all])


## Host: sumy kontrolne kroku — różne = rozjazd (raport w logu, koniec u wszystkich).
func _add_sum(at: int, player: int, sum: int) -> void:
	var got: Dictionary = _sums.get(at, {})
	got[player] = sum
	_sums[at] = got
	var values := got.values()
	for v: int in values:
		if v != values[0]:
			desync_step = at
			push_warning("[net] rozjazd w kroku %d: sumy %s" % [at, got])
			_end("Rozjazd gry (krok %d)" % at)
			return
	if got.size() >= players.size():
		_sums.erase(at)


func _end(reason: String, tell := true) -> void:
	if over != "":
		return
	over = reason
	if tell and is_host and peer != null:
		_broadcast(["end", reason])
		peer.poll()  # wypchnij pakiet przed ewentualnym zamknięciem
	ended.emit(reason)


func _send_host(msg: Array) -> void:
	_send_to(1, msg)


func _broadcast(msg: Array) -> void:
	_send_to(0, msg)


func _send_to(id: int, msg: Array) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.set_target_peer(id)
	peer.put_packet(var_to_bytes(msg))


# ================================================================ odkrywanie gier w Wi-Fi

## Rozgłaszanie UDP: host co sekundę ogłasza grę, gość zbiera listę `games` (ip → nazwa). Ręczny IP zapasowo.
class Discovery:
	extends RefCounted
	const PORT := 24651
	const MAGIC := "TDGAME"

	var udp := PacketPeerUDP.new()
	var games := {}  ## ip → {name, port, seen (ms)}
	var _next_ad := 0

	## Gość: słucha ogłoszeń.
	func listen() -> Error:
		return udp.bind(PORT)

	## Host: co sekundę ogłasza (`dest` = adres rozgłoszeniowy; test używa 127.0.0.1).
	func advertise(name: String, game_port := NetSession.PORT, dest := "255.255.255.255") -> void:
		var now := Time.get_ticks_msec()
		if now < _next_ad:
			return
		_next_ad = now + 1000
		udp.set_broadcast_enabled(true)
		udp.set_dest_address(dest, PORT)
		udp.put_packet(("%s|%d|%s" % [MAGIC, game_port, name]).to_utf8_buffer())

	func poll() -> void:
		while udp.get_available_packet_count() > 0:
			var text := udp.get_packet().get_string_from_utf8()
			var ip := udp.get_packet_ip()
			var parts := text.split("|", true, 2)
			if parts.size() == 3 and parts[0] == MAGIC and parts[1].is_valid_int():
				games[ip] = {"name": parts[2], "port": int(parts[1]), "seen": Time.get_ticks_msec()}
		for ip: String in games.keys():
			if Time.get_ticks_msec() - games[ip]["seen"] > 4000:
				games.erase(ip)

	func close() -> void:
		udp.close()
