#!/usr/bin/env bash
# Removes SmartumSwitch (packages installed by install.sh are kept).
set -uo pipefail
systemctl --user disable --now smartum-switch.service 2>/dev/null
rm -f "$HOME/.config/systemd/user/smartum-switch.service"; systemctl --user daemon-reload
KP=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/smartum-switch/
if command -v gsettings >/dev/null; then
  LIST=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
  NEW=$(python3 -c "import ast,sys; l=ast.literal_eval(sys.argv[1].replace('@as ','')); print(str([x for x in l if x!=sys.argv[2]]))" "$LIST" "$KP")
  gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW"
  gsettings reset-recursively "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KP" 2>/dev/null
fi
rm -f "$HOME/.local/bin/smartum-switch"
sudo rm -f /etc/udev/rules.d/70-smartum-switch.rules && sudo udevadm control --reload
echo "Removed. Settings kept in ~/.config/smartum-switch (delete manually if you want)."
