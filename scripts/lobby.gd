class_name Lobby
extends RefCounted
## Lobby gry ze znajomym w Wi-Fi (multiplayer T6): host tworzy grę (ogłasza ją w sieci), gość wybiera ją z listy
## albo wpisuje IP. Każdy wybiera rasę i dowódcę na tej samej stronie menu co w solo; host wybiera mapę
## i trudność i startuje. Ustawienia partii (ziarno, mapa, dowódcy, rasa wroga) idą od hosta w pakiecie
## „start”, z nich obaj budują ten sam Sim (`Main.start_net`). Widok lobby: strony „net” i „wait” w `Hud`.
## v1: tylko Bitwa, 2 graczy (host = gracz 0, gość = gracz 2).

var m: Main
var session: NetSession = null
var discovery: NetSession.Discovery = null
var role := ""  ## "" / "host" / "guest"
var status := ""  ## komunikat w lobby (błąd połączenia itp.)
var _sent_pick := ""


func _init(main: Main) -> void:
	m = main


func host_game() -> void:
	leave()
	session = NetSession.new()
	if session.host() != OK:
		status = "Nie udało się utworzyć gry (port zajęty?)"
		session = null
		return
	discovery = NetSession.Discovery.new()
	role = "host"
	status = ""


## Gość: nasłuch ogłoszeń gier w Wi-Fi (lista w `games()`).
func browse() -> void:
	if discovery == null:
		discovery = NetSession.Discovery.new()
		if discovery.listen() != OK:
			status = "Nie można szukać gier (port zajęty)"


func join(ip: String, port := NetSession.PORT) -> void:
	var d := discovery
	discovery = null  # nie zamykaj listy przy leave — tylko sesję
	leave()
	discovery = d
	session = NetSession.new()
	if not ip.is_valid_ip_address() or session.join(ip, port) != OK:
		status = "Zły adres IP" if not ip.is_valid_ip_address() else "Nie udało się połączyć"
		session = null
		return
	role = "guest"
	status = "Łączenie z %s…" % ip
	_sent_pick = ""


func leave() -> void:
	if session != null:
		session.close()
	session = null
	if discovery != null:
		discovery.close()
	discovery = null
	role = ""
	status = ""


## Po starcie partii sesja należy do `Main.net` — lobby ją puszcza (bez zamykania).
func detach() -> void:
	session = null
	if discovery != null:
		discovery.close()
	discovery = null
	role = ""


func active() -> bool:
	return role != ""


func games() -> Dictionary:
	return discovery.games if discovery != null else {}


## Czy gość jest i wybrał dowódcę (host może startować).
func guest_ready() -> bool:
	return role == "host" and session.guest_count() > 0 and session.picks.size() == session.guest_count()


func guest_text() -> String:
	if role != "host":
		return ""
	if session.guest_count() == 0:
		return "Czekam na drugiego gracza…"
	for p: int in session.picks:
		return "Drugi gracz: %s" % commander_text(session.picks[p])
	return "Drugi gracz dołączył — wybiera dowódcę…"


static func commander_text(id: String) -> String:
	var c: Dictionary = Cfg.COMMANDERS[id]
	var race := Races.ALL.find_custom(func(r: Dictionary) -> bool: return r["id"] == c["race"])
	return "%s (%s)" % [Races.ALL[race]["name"], c["name"]]


## Adres IP tego telefonu w Wi-Fi (do wpisania ręcznie u gościa). Najpierw interfejs Wi-Fi (`wlan*`) — telefon
## ma też adres danych komórkowych (często 10.x), który gościowi w Wi-Fi nic nie da; potem 192.168.x, 172.16–31.x, 10.x.
static func local_ip() -> String:
	var best := ""
	var best_rank := 99
	for iface: Dictionary in IP.get_local_interfaces():
		var wifi := String(iface["name"]).begins_with("wlan") or String(iface["name"]).begins_with("wifi")
		for a: String in iface["addresses"]:
			var rank := _private_rank(a)
			if rank < 0:
				continue
			rank += 0 if wifi else 10
			if rank < best_rank:
				best_rank = rank
				best = a
	return best if best != "" else "?"


## Prywatny adres IPv4: 0 = 192.168.x, 1 = 172.16–31.x, 2 = 10.x; -1 = inny.
static func _private_rank(a: String) -> int:
	if not a.is_valid_ip_address() or a.contains(":"):
		return -1
	if a.begins_with("192.168."):
		return 0
	if a.begins_with("172.") and a.split(".")[1].to_int() in range(16, 32):
		return 1
	if a.begins_with("10."):
		return 2
	return -1


## Co klatkę w menu: ogłaszanie gry, lista gier, wybór gościa do hosta, start u gościa.
func poll() -> void:
	if discovery != null:
		if role == "host":
			var ip := local_ip()
			var subnet := ip.substr(0, ip.rfind(".")) + ".255" if ip != "?" else "255.255.255.255"
			discovery.advertise("Gra %s" % ip, NetSession.PORT, subnet)
		else:
			discovery.poll()
	if session == null:
		return
	session.poll()
	if session.over != "":
		status = session.over
		var d := discovery
		discovery = null
		leave()
		discovery = d
		return
	if role == "guest":
		if session.me >= 2:
			status = "Połączono"
			if m.commander_id != _sent_pick and m.commander_id != "":
				session.send_pick(m.commander_id)
				_sent_pick = m.commander_id
		if session.started and not session.start_cfg.is_empty():
			m.start_net(session, session.start_cfg)


## Host: start partii na wybranej trudności (gość musi być gotowy).
func start(difficulty: int) -> bool:
	if not guest_ready():
		return false
	var rnd := RandomNumberGenerator.new()
	rnd.randomize()
	var guests := {}
	for p: int in session.picks:
		guests[p] = session.picks[p]
	var cfg := {"seed": rnd.randi() % 1000000000, "level": m.level_index, "difficulty": difficulty,
		"host": m.commander_id, "guests": guests,
		"rival": Races.ALL[Races.random_rival(m.race_index, rnd)]["id"]}
	m.start_net(session, cfg)
	return true
