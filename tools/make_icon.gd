extends SceneTree
## Ikona aplikacji: art/icon/*.svg (z tools/svg_gen/icon.py) → PNG w rozmiarach dla projektu i Androida.
##
##   godot --headless --path . --script res://tools/make_icon.gd
##
##   icon.svg    → icon.png (512, `application/config/icon`, launcher 192 skaluje eksport)
##   icon_bg.svg → icon_bg.png (432, tło ikony adaptacyjnej)
##   icon_fg.svg → icon_fg.png (432, pierwszy plan ikony adaptacyjnej)

const DIR := "res://art/icon/"


func _init() -> void:
	for name in ["icon", "icon_bg", "icon_fg"]:
		var img := Image.new()
		var err := img.load_svg_from_string(FileAccess.get_file_as_string(DIR + name + ".svg"), 1.0)
		if err != OK:
			push_error("make_icon: nie wczytano %s.svg (%d)" % [name, err])
			quit(1)
			return
		img.save_png(DIR + name + ".png")
		print("make_icon: %s.png %d×%d" % [name, img.get_width(), img.get_height()])
	quit(0)
