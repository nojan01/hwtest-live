#!/bin/sh
# WebKitGTK (JSON Viewer) rendert auf iLO-/Matrox-/VM-Grafik ohne GPU-Beschleunigung
# sonst ggf. nur ein leeres Fenster.
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export QT_QPA_PLATFORM=xcb
export LIBGL_ALWAYS_SOFTWARE=1

[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# Layout setzen und Caps Lock deaktivieren (iLO-Konsole laesst sonst den
# Lock-Modifier haengen -> alles gross). Manuell: hpe-live-keyboard-reset
hpe-live-keyboard-reset >/dev/null 2>&1 || true

exec openbox-session
