# Hardwaretest Live: nach dem Autologin auf tty1 die grafische Oberfläche starten.
# (Ersetzt die gleichnamige Datei der live-config-Komponente "xinit".)
# Abschalten mit Kernel-Parameter "hpe-live.nox".
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ] \
   && ! grep -qw 'hpe-live.nox' /proc/cmdline; then
    startx -- -nolisten tcp >"$HOME/.xsession-errors" 2>&1
    echo
    echo "Grafische Oberfläche beendet. Neu starten mit: startx"
    echo "Log: ~/.xsession-errors"
fi
