extends SceneTree
## Test gry sieciowej (multiplayer T4): host i gość `NetSession` w jednym procesie na localhost, headless.
##   godot --headless --path . --script res://tests/net_test.gd
## Sprawdza: lockstep (te same sumy, nikt nie wyprzedza o więcej niż DELAY, kroki się nie gubią),
## numer gracza nadaje host (R5), sztuczny rozjazd kończy partię u obu, zerwanie kończy partię,
## odkrywanie gier przez UDP. Kod wyjścia 1 = błąd.

const PORT := 24760
var failures := 0


func _initialize() -> void:
	_test_lockstep()
	_test_disconnect()
	_test_discovery()
	print("OK" if failures == 0 else "BŁĘDY: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + what)


## Para połączonych sesji z Sim (host = gracz 0, gość = gracz 2), obie wystartowane. [] = nie wyszło.
func _pair(port: int) -> Array:
	var host := NetSession.new()
	var guest := NetSession.new()
	_check(host.host(port) == OK, "host nasłuchuje")
	_check(guest.join("127.0.0.1", port) == OK, "gość się łączy")
	if not _until(func() -> bool: return guest.me == 2 and host.guest_count() == 1, [host, guest]):
		_check(false, "gość dostał numer gracza od hosta")
		return []
	var sims: Array[Sim] = []
	for i in 2:
		var s := Sim.new(2, 77, 1, "sapper", "battle", [], Races.ALL[1]["id"])
		s.add_player("iron_grip")
		sims.append(s)
	host.start(sims[0])
	guest.attach(sims[1])
	_check(_until(func() -> bool: return guest.started, [host, guest]), "gość dostał start")
	_check(guest.players == host.players and host.players == [0, 2], "lista graczy zgodna u obu")
	return [host, guest]


func _until(cond: Callable, sessions: Array, ms := 3000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		for s: NetSession in sessions:
			s.poll()
		if cond.call():
			return true
		OS.delay_msec(2)
	return false


func _test_lockstep() -> void:
	var pair := _pair(PORT)
	if pair.is_empty():
		return
	var host: NetSession = pair[0]
	var guest: NetSession = pair[1]
	var a := host.sim
	var b := guest.sim
	var max_lead := 0
	var i := 0
	var end := Time.get_ticks_msec() + 60000
	while guest.step < 900 and host.over == "" and Time.get_ticks_msec() < end:
		i += 1
		host.poll()
		guest.poll()
		# różne tempo: host liczy do 3 kroków na obrót, gość co trzeci obrót tylko 1 — host musi czekać
		for k in 3:
			if host.try_step() and host.step % 45 == 0:
				for n in a.nodes.size():
					host.send({"type": "build_extractor", "node": n})
				host.send({"type": "order_hero", "at": a.p_base + Vector2(250, (host.step % 200) - 100)})
		if i % 3 == 0 and guest.try_step() and guest.step == 60:
			# gość podszywa się pod gracza 0 — host i tak wpisze gracza 2 (R5)
			guest.send({"player": 0, "type": "set_stance", "stance": "defend"})
			guest.send({"type": "build", "kind": "tower", "cell": b.free_cell_near(b.p_base + Vector2(160, 0), 300.0)})
		max_lead = maxi(max_lead, host.step - guest.step)
	_check(guest.step >= 900 and host.over == "" and guest.over == "", "900 kroków lockstepu bez końca partii (%d, %s)" % [guest.step, host.over])
	_until(func() -> bool: return guest.step == host.step or not guest.try_step(), [host, guest])
	while guest.step < host.step and guest.try_step():
		pass
	_check(guest.step == host.step and a.checksum() == b.checksum(), "po dogonieniu: ten sam krok i suma kontrolna (%d/%d)" % [host.step, guest.step])
	_check(max_lead <= NetSession.DELAY, "host nie wyprzedza gościa o więcej niż DELAY (max %d)" % max_lead)
	_check(a.players[2].stance == "defend" and a.players[0].stance == "attack" and b.players[2].stance == "defend",
		"komenda gościa z cudzym numerem wykonana jako gość (R5)")
	var towers := a.buildings.filter(func(x: Sim.Building) -> bool: return x.kind == "tower" and x.owner == 2)
	_check(towers.size() == 1, "wieża gościa stoi u hosta (właściciel = gracz 2)")
	_check(a.buildings.filter(func(x: Sim.Building) -> bool: return x.kind == "extractor").size() > 0, "komendy hosta wykonane")

	# sztuczny rozjazd: gość zmienia sobie złoto → przy najbliższej sumie koniec u obu
	b.players[2].gold += 100.0
	_until(func() -> bool:
		host.try_step()
		guest.try_step()
		return host.over != "" and guest.over != "", [host, guest], 5000)
	_check(host.over.begins_with("Rozjazd") and guest.over.begins_with("Rozjazd") and host.desync_step > 0,
		"rozjazd kończy partię u obu z numerem kroku (%s / %s)" % [host.over, guest.over])
	host.close()
	guest.close()


func _test_disconnect() -> void:
	var pair := _pair(PORT + 1)
	if pair.is_empty():
		return
	var host: NetSession = pair[0]
	var guest: NetSession = pair[1]
	_until(func() -> bool:
		host.try_step()
		guest.try_step()
		return guest.step > 60, [host, guest])
	guest.close()
	_check(_until(func() -> bool: return host.over != "", [host], 8000) and host.over == "Połączenie przerwane",
		"zerwanie połączenia kończy partię u hosta (%s)" % host.over)
	var stuck := host.step
	host.try_step()
	host.try_step()
	_check(host.step <= stuck, "po końcu partii kroki stoją")
	host.close()


func _test_discovery() -> void:
	var listener := NetSession.Discovery.new()
	var ad := NetSession.Discovery.new()
	_check(listener.listen() == OK, "odkrywanie: nasłuch UDP")
	var end := Time.get_ticks_msec() + 3000
	while listener.games.is_empty() and Time.get_ticks_msec() < end:
		ad.advertise("Gra testowa", NetSession.PORT, "127.0.0.1")
		listener.poll()
		OS.delay_msec(20)
	_check(listener.games.has("127.0.0.1") and listener.games["127.0.0.1"]["name"] == "Gra testowa"
		and listener.games["127.0.0.1"]["port"] == NetSession.PORT, "odkrywanie: gość widzi grę hosta (%s)" % listener.games)
	listener.close()
	ad.close()
