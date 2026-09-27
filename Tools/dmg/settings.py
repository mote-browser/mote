# dmgbuild settings for Mote.dmg, used by `make dmg`:
#
#   uvx 'dmgbuild>=1.6.7' -s Tools/dmg/settings.py -D app=build/Mote.app -D art=build/dmg-art Mote build/Mote.dmg
#
# dmgbuild writes the Finder layout directly, so no Finder or AppleScript is
# involved. The background and volume icon come from art.swift; icon
# positions here must match the spots it leaves for them.

import os.path

app = defines["app"]
art = defines["art"]

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [os.path.basename(app)]

format = "ULFO"  # lzfse: fast to open, and supported since macOS 10.11
filesystem = "HFS+"
icon = os.path.join(art, "VolumeIcon.icns")
background = os.path.join(art, "background.tiff")

# The window frame includes Finder's ~28 pt title bar over the 660×400 picture.
window_rect = ((200, 140), (660, 428))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 180),
    "Applications": (490, 180),
}
