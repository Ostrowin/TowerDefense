# Potwory celów mapy (Cfg.MONSTERS, docs/designs/wielka-mapa-smok.md). Neutralne — bez magenty drużyny.
#   monster_dragon        — przebudzony: głowa w górze, skrzydła rozłożone, żar w paszczy (fantasy)
#   monster_dragon_sleep  — śpiący: zwinięty, głowa na łapach, skrzydło złożone
#
#   python tools/svg_gen/monsters.py   potem: tools/bake_art.gd i --import
from common import *

SCALE = "#7a1e14"
SCALE_D = "#521208"
SCALE_L = "#a8382a"
BELLY = "#d89a4a"
BELLY_D = "#a8702e"
MEMBRANE = "#5a1a12"
MEMBRANE_L = "#7a2a1c"
HORN = BONE
EMBER = "#ffb02a"
EMBER_L = "#fff0a0"

W, H = 256, 200
ANCHOR = (128, 186)  # stopy (środek legowiska) — Sim.Objective.pos
WORLD = 0.62  # ok. 160 px szerokości w świecie


def _tail(curl=0):
    return g(f'''    <path d="M86 150 C60 156 34 150 22 134 C14 122 18 108 30 104 C26 116 30 128 44 134 C58 140 74 138 88 134 Z" fill="{SCALE_D}"/>
    <path d="M22 134 L6 128 L18 140 Z" fill="{HORN}"/>''')


def _spikes(pts):
    return "\n".join(f'  <path d="M{x} {y} L{x + 6} {y - 12} L{x + 12} {y} Z" fill="{HORN}" stroke="{INK}" stroke-width="2" stroke-linejoin="round"/>' for x, y in pts)


def dragon():
    # skrzydła: kość ramienia do szczytu, palce rozchodzą się do tyłu, błona wygięta między palcami
    wing_far = g(f'''    <path d="M112 94 L92 30 Q78 46 64 34 Q62 56 42 50 Q50 70 34 76 Q60 98 112 94 Z" fill="{MEMBRANE}"/>
    <path d="M112 94 L92 30 M92 30 L64 34 M92 30 L42 50 M92 30 L34 76" stroke-width="2.5" fill="none"/>''')
    wing_near = g(f'''    <path d="M140 94 L150 14 Q128 32 112 22 Q114 46 92 46 Q104 66 86 74 Q110 98 140 94 Z" fill="{MEMBRANE_L}"/>
    <path d="M140 94 L150 14 M150 14 L112 22 M150 14 L92 46 M150 14 L86 74" stroke-width="3" fill="none"/>''') + f'''
  <path d="M148 22 L156 8" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>
  <path d="M150 14 L154 6 L158 14 Z" fill="{HORN}" stroke="{INK}" stroke-width="1.5"/>
  <path d="M136 34 Q124 44 112 40 M128 58 Q114 64 104 62" stroke="{SCALE_L}" stroke-width="2" fill="none" opacity="0.6"/>'''
    legs_far = g(f'''    <path d="M84 140 L78 172 L70 182 L94 182 L94 170 L100 146 Z" fill="{SCALE_D}"/>
    <path d="M150 138 L156 168 L150 182 L172 182 L170 166 L166 136 Z" fill="{SCALE_D}"/>''')
    body = g(f'''    <path d="M70 128 C66 104 88 88 118 86 C150 84 176 96 180 118 C184 142 162 158 126 160 C96 162 74 150 70 128 Z" fill="{SCALE}"/>''') + f'''
  <path d="M86 108 C98 96 126 92 150 98 C134 98 108 102 92 114 Z" fill="{SCALE_L}" opacity="0.8"/>
  <path d="M92 148 C110 156 146 156 166 144 C160 136 150 132 140 134 C120 140 104 140 92 148 Z" fill="{BELLY}" stroke="{INK}" stroke-width="2"/>
  <path d="M108 142 L110 152 M124 140 L124 154 M140 138 L140 152 M154 136 L156 148" stroke="{BELLY_D}" stroke-width="2"/>''' \
        + _spikes([(92, 92), (110, 86), (130, 84), (150, 88)])
    legs_near = g(f'''    <path d="M100 146 L96 172 L88 184 L116 184 L114 172 L120 150 Z" fill="{SCALE}"/>
    <path d="M160 132 L170 160 L168 184 L194 184 L188 168 L178 130 Z" fill="{SCALE}"/>''') + f'''
  <path d="M88 184 L84 188 M96 184 L94 189 M104 184 L104 189 M168 184 L164 189 M176 184 L174 189 M184 184 L184 189" stroke="{HORN}" stroke-width="3" stroke-linecap="round"/>'''
    neck = g(f'''    <path d="M166 112 C176 96 178 76 190 62 C198 52 210 50 216 58 C206 64 200 76 196 92 C192 108 186 124 176 132 Z" fill="{SCALE}"/>''') + f'''
  <path d="M176 104 C182 90 186 76 194 66" stroke="{BELLY}" stroke-width="6" fill="none" stroke-linecap="round"/>''' \
        + _spikes([(176, 92), (184, 74)])
    head = g(f'''    <path d="M196 42 C206 30 228 30 240 40 L252 48 L246 54 L236 54 L242 62 L230 66 C220 70 204 66 198 58 Z" fill="{SCALE}"/>
    <path d="M204 38 L196 16 L212 34 Z M216 34 L214 10 L226 34 Z" fill="{HORN}"/>''') + f'''
  <path d="M200 44 C210 36 226 36 236 42" stroke="{SCALE_L}" stroke-width="3" fill="none"/>
  <path d="M236 54 L242 62 L230 66 Z" fill="{EMBER}" stroke="{INK}" stroke-width="1.5"/>
  <circle cx="246" cy="58" r="6" fill="{EMBER}" opacity="0.35"/>
  <circle cx="250" cy="56" r="3" fill="{EMBER_L}" opacity="0.7"/>
  <path d="M216 44 C220 41 226 41 228 45 C224 48 219 48 216 44 Z" fill="{EMBER}" stroke="{INK}" stroke-width="1.2"/>
  <circle cx="222" cy="45" r="7" fill="{EMBER}" opacity="0.25"/>
  <path d="M240 46 L246 47" stroke="{INK}" stroke-width="1.5"/>'''
    shadow = f'  <ellipse cx="{ANCHOR[0]}" cy="{ANCHOR[1] - 2}" rx="96" ry="12" fill="#000000" opacity="0.28"/>'
    s = "\n".join([shadow, wing_far, _tail(), legs_far, body, wing_near, neck, head, legs_near])
    svg("monster_dragon", s, W, H, anchor=ANCHOR, world=WORLD,
        note="Smok (fantasy, cel mapy): przebudzony, głowa w górze, skrzydła rozłożone, żar w paszczy i oczach.")


def dragon_sleep():
    wing = g(f'''    <path d="M84 104 C100 70 140 60 176 74 C164 84 156 96 150 110 C128 112 104 112 84 104 Z" fill="{MEMBRANE_L}"/>
    <path d="M90 102 C110 80 140 72 172 76 M110 108 C122 90 140 82 160 84" stroke-width="2.5" fill="none"/>''')
    body = g(f'''    <path d="M62 140 C58 112 86 96 122 96 C158 96 186 112 186 138 C186 160 160 172 124 172 C88 172 66 162 62 140 Z" fill="{SCALE}"/>''') + f'''
  <path d="M80 118 C96 106 124 102 150 106 C130 108 104 112 88 124 Z" fill="{SCALE_L}" opacity="0.8"/>
  <path d="M86 162 C110 170 150 170 172 158 C166 150 154 146 144 148 C122 154 104 154 86 162 Z" fill="{BELLY}" stroke="{INK}" stroke-width="2"/>''' \
        + _spikes([(84, 102), (104, 96), (126, 94), (148, 96)])
    tail = g(f'''    <path d="M70 156 C48 168 40 182 70 186 C110 190 160 188 196 180 C170 178 120 180 90 176 C80 174 76 168 84 162 Z" fill="{SCALE_D}"/>
    <path d="M196 180 L214 172 L206 186 Z" fill="{HORN}"/>''')
    paws = g(f'''    <path d="M168 160 L176 176 L172 184 L206 184 L202 172 L186 158 Z" fill="{SCALE}"/>''') + f'''
  <path d="M206 184 L210 188 M198 184 L200 189 M190 184 L190 189" stroke="{HORN}" stroke-width="3" stroke-linecap="round"/>'''
    head = g(f'''    <path d="M176 150 C182 136 200 132 216 138 L236 150 L232 160 L214 166 C198 170 182 166 176 150 Z" fill="{SCALE}"/>
    <path d="M186 142 L172 128 L192 138 Z M198 138 L190 120 L206 136 Z" fill="{HORN}"/>''') + f'''
  <path d="M184 144 C194 138 208 138 218 142" stroke="{SCALE_L}" stroke-width="3" fill="none"/>
  <path d="M200 148 C204 151 210 151 214 148" stroke="{INK}" stroke-width="2" fill="none"/>
  <path d="M232 154 L238 154" stroke="{INK}" stroke-width="1.5"/>
  <circle cx="242" cy="150" r="3" fill="#cfcfcf" opacity="0.5"/>
  <circle cx="248" cy="142" r="2" fill="#cfcfcf" opacity="0.35"/>'''
    shadow = f'  <ellipse cx="{ANCHOR[0]}" cy="{ANCHOR[1] - 2}" rx="100" ry="12" fill="#000000" opacity="0.28"/>'
    s = "\n".join([shadow, tail, body, wing, paws, head])
    svg("monster_dragon_sleep", s, W, H, anchor=ANCHOR, world=WORLD,
        note="Smok (fantasy, cel mapy): śpi zwinięty, głowa na łapach, skrzydło złożone, dym z nozdrzy.")


if __name__ == "__main__":
    dragon()
    dragon_sleep()
