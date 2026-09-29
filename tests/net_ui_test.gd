extends SceneTree
## Gra ze znajomym od menu do końca (multiplayer T6): dwie prawdziwe sceny gry w jednym procesie
## na localhost. Host: Ze znajomym → Utwórz grę → rasa i dowódca → mapa; gość: dołącza po IP,
## wybiera dowódcę → czeka. Host startuje; obaj grają tę samą partię (ta sama suma kontrolna),
## prędkość ukryta, pauza u jednego pauzuje obu, wyjście gościa kończy partię u hosta komunikatem.
##
##   godot --headless --path . --fixed-fps 60 --script res://tests/net_ui_test.gd
## Szukaj „SCRIPT ERROR” — test sam nie przechwyci błędów silnika. Kod wyjścia 1 = błąd.

var host: Node
var guest: Node
var frame := 0
var failures := 0
var phase := "lobby"
var phase_frame := 0


func _initialize() -> void:
	Progress.path = "user://test_net_progress.cfg"
	Settings.path = "user://test_net_settings.cfg"
	for p in [Progress.path, Settings.path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Progress.reset_cache()
	Progress.set_tutorial_done(true)
	host = load("res://main.tscn").instantiate()
	guest = load("res://main.tscn").instantiate()
	root.add_child(host)
	root.add_child(guest)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + what)


func _finish() -> void:
	for p in [Progress.path, Settings.path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("OK" if failures == 0 else "BŁĘDY: %d" % failures)
	quit(1 if failures > 0 else 0)


func _go(p: String) -> void:
	phase = p
	phase_frame = frame


func _process(_delta: float) -> bool:
	frame += 1
	var waited := frame - phase_frame
	match phase:
		"lobby":
			if frame == 3:
				host.hud.open_net()
				host.select_race(Races.ALL.find_custom(func(r: Dictionary) -> bool: return r["id"] == "mole"))
				host.hud.host_net()
				_check(host.lobby.role == "host" and host.hud.menu_page == "army", "host: utworzona gra → rasa i dowódca")
				host.hud.menu_go("map")
				host.select_level(Levels.coop_indices()[1])
				guest.hud.open_net()
				guest.select_race(Races.ALL.find_custom(func(r: Dictionary) -> bool: return r["id"] == "gibbon"))
				guest.select_commander("warbeat")
				guest.hud.ip_edit.text = "127.0.0.1"
				guest.hud.join_net(guest.hud.ip_edit.text)
				_check(guest.lobby.role == "guest", "gość: łączy się po IP")
				guest.hud.menu_go("wait")
			elif frame > 3 and host.lobby.guest_ready():
				_check(host.hud.lobby_label.text.contains("Gibony"), "host widzi wybór gościa (%s)" % host.hud.lobby_label.text)
				host.hud.pick_difficulty(1)
				_go("play")
			elif waited > 300:
				_check(false, "gość gotowy w lobby (%s / %s)" % [host.lobby.guest_text(), guest.lobby.status])
				_finish()
		"play":
			if waited == 1:
				_check(host.state == host.State.PLAY and host.net != null and host.me == 0, "host w grze sieciowej")
			if waited == 60:
				_check(guest.state == guest.State.PLAY and guest.net != null and guest.me == 2, "gość w grze sieciowej jako gracz 2")
				_check(guest.sim.level["id"] == host.sim.level["id"] and guest.sim.players.size() == 3
					and guest.sim.players[2].commander == "warbeat" and host.sim.players[0].commander == guest.sim.players[0].commander,
					"obaj mają tę samą mapę i dowódców")
				_check(guest.sim.level.get("coop", false) and guest.sim.has_base(2) and guest.sim.base_of(guest.me) == 2,
					"mapa coop: gość ma własną bazę")
				_check(not host.hud.speed_button.visible and not guest.hud.speed_button.visible, "prędkość ukryta w sieci (R4)")
				host.controls.cycle_speed()
				_check(host.speed_mult == 1, "prędkości nie da się zmienić w sieci")
				guest.controls.toggle_stance()
			if waited == 400:
				var steps := mini(host.net.step, guest.net.step)
				_check(steps >= 180, "partia idzie x1 (%d kroków)" % steps)
				_check(host.sim.players[2].stance == "defend" and host.sim.players[0].stance == "attack", "rozkaz gościa dotarł do hosta")
				guest.set_paused(true)
			if waited == 460:
				_check(host.state == host.State.PAUSED and guest.state == guest.State.PAUSED, "pauza gościa pauzuje obu")
				_check(host.net.step == guest.net.step and host.sim.checksum() == guest.sim.checksum(),
					"w pauzie ten sam krok i suma (%d/%d)" % [host.net.step, guest.net.step])
				host.set_paused(false)
			if waited == 520:
				_check(host.state == host.State.PLAY and guest.state == guest.State.PLAY, "wznowienie u obu")
				guest.show_menu()
				_go("left")
		"left":
			if host.state == host.State.OVER:
				_check(host.hud.over_title.text == "Połączenie przerwane" and not host.hud.again_button.visible,
					"wyjście gościa kończy partię u hosta komunikatem")
				host.show_menu()
				_check(host.net == null and host.lobby.role == "", "menu po grze sieciowej: połączenie zamknięte")
				_finish()
			elif waited > 600:
				_check(false, "host zauważa wyjście gościa")
				_finish()
	return false
