# HA KioskOS — .bash_profile pro uživatele pi
# Spustí X server na TTY1 po autologinu

# Načti .bashrc pokud existuje
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

# Spusť X pouze na TTY1 a pokud DISPLAY není nastaven
if [ "$(tty)" = "/dev/tty1" ] && [ -z "${DISPLAY:-}" ]; then
    exec startx -- -nolisten tcp vt1
fi
