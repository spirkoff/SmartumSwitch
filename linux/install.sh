#!/usr/bin/env bash
# SmartumSwitch installer (Ubuntu 24.04 / elementary OS 8 and similar). Run as your normal user.
#   ./install.sh                 install everything
#   ./install.sh --no-hotkey     do not add the Pause hotkey
#   ./install.sh --no-auto       do not enable auto-correction service
set -euo pipefail
HOTKEY=1; AUTO=1
for a in "$@"; do case "$a" in --no-hotkey) HOTKEY=0;; --no-auto) AUTO=0;; *) echo "unknown option $a"; exit 1;; esac; done
cd "$(dirname "$0")"
[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user (sudo is asked only where needed)."; exit 1; }

echo "==> Packages"
sudo apt-get install -y python3-evdev wl-clipboard libhunspell-1.7-0 hunspell-ru hunspell-en-us libnotify-bin

echo "==> udev rule (access to /dev/uinput and keyboards for the active session user)"
sudo install -m 644 udev/70-smartum-switch.rules /etc/udev/rules.d/70-smartum-switch.rules
sudo udevadm control --reload
sudo udevadm trigger --name-match=uinput --action=add || true
sudo udevadm trigger --subsystem-match=input --action=change || true

echo "==> Program"
install -D -m 755 smartum-switch "$HOME/.local/bin/smartum-switch"

if [ "$AUTO" = 1 ]; then
  echo "==> Auto-correction service"
  install -D -m 644 systemd/smartum-switch.service "$HOME/.config/systemd/user/smartum-switch.service"
  systemctl --user daemon-reload
  systemctl --user enable smartum-switch.service
  systemctl --user restart smartum-switch.service || echo "   (will start at next login)"
fi

if [ "$HOTKEY" = 1 ] && command -v gsettings >/dev/null; then
  echo "==> Hotkey Pause -> smartum-switch (manual fix)"
  KP=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/smartum-switch/
  LIST=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
  NEW=$(python3 -c "import ast,sys; l=sys.argv[1].replace('@as ',''); l=ast.literal_eval(l); p=sys.argv[2]; l=l+[p] if p not in l else l; print(str(l))" "$LIST" "$KP")
  gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW"
  S=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KP
  gsettings set "$S" name 'SmartumSwitch: исправить раскладку'
  gsettings set "$S" command "$HOME/.local/bin/smartum-switch"
  gsettings set "$S" binding 'Pause'
fi
echo
echo "Done. Pause = fix selection / last word. Shift+Pause = auto-correction on/off."
echo "Exceptions: ~/.config/smartum-switch/exceptions.txt"
