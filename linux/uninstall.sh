#!/usr/bin/env bash
# SmartumSwitch uninstaller for Linux.
# Removes the user-space program, autostart entries, hotkey and optional udev rule.
# Keeps ~/.config/smartum-switch unless --purge is passed.
set -uo pipefail

PURGE=0
NO_SUDO=0
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    --no-sudo) NO_SUDO=1 ;;
    -h|--help)
      cat <<'USAGE'
Использование: uninstall.sh [--purge] [--no-sudo]
  --purge     удалить также ~/.config/smartum-switch и ~/.cache/smartum-switch*
  --no-sudo   не удалять системное правило /etc/udev/rules.d/70-smartum-switch.rules
USAGE
      exit 0
      ;;
    *) echo "Неизвестный параметр: $a" >&2; exit 1 ;;
  esac
done

run_priv() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif sudo -n true >/dev/null 2>&1; then
    sudo "$@"
  elif (: </dev/tty) 2>/dev/null; then
    sudo "$@" </dev/tty
  else
    sudo "$@"
  fi
}

echo "==> Остановка и удаление автозапуска SmartumSwitch"
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user disable --now smartum-switch.service 2>/dev/null || true
fi
rm -f "$HOME/.config/systemd/user/smartum-switch.service"
rm -f "$HOME/.config/systemd/user/graphical-session.target.wants/smartum-switch.service"
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload 2>/dev/null || true
fi
rm -f "$HOME/.config/autostart/smartum-switch.desktop"

if command -v pkill >/dev/null 2>&1; then
  pkill -u "$(id -u)" -f "$HOME/.local/bin/smartum-switch daemon" 2>/dev/null || true
fi

KP=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/smartum-switch/
if command -v gsettings >/dev/null 2>&1 \
  && { [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; } \
  && gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.settings-daemon.plugins.media-keys'; then
  LIST=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "@as []")
  if command -v python3 >/dev/null 2>&1; then
    NEW=$(python3 -c "import ast,sys; l=ast.literal_eval(sys.argv[1].replace('@as ','')); print(str([x for x in l if x!=sys.argv[2]]))" "$LIST" "$KP" 2>/dev/null || true)
    [ -n "$NEW" ] && gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW" 2>/dev/null || true
  fi
  gsettings reset-recursively "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KP" 2>/dev/null || true
fi

rm -f "$HOME/.local/bin/smartum-switch"
rm -rf "$HOME/.local/share/smartum-switch"

UDEV_RULE="/etc/udev/rules.d/70-smartum-switch.rules"
if [ -f "$UDEV_RULE" ]; then
  if [ "$NO_SUDO" = 1 ]; then
    echo "Правило $UDEV_RULE оставлено (--no-sudo). Удалить вручную: sudo rm -f $UDEV_RULE && sudo udevadm control --reload"
  elif [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
    if run_priv rm -f "$UDEV_RULE"; then
      run_priv udevadm control --reload 2>/dev/null || true
    else
      echo "Не удалось удалить $UDEV_RULE (можно удалить вручную: sudo rm -f $UDEV_RULE)."
    fi
  fi
fi

if [ "$PURGE" = 1 ]; then
  rm -rf "$HOME/.config/smartum-switch" "$HOME/.cache/smartum-switch" "$HOME/.cache/smartum-switch.log"
  echo "SmartumSwitch полностью удалён, включая настройки и кэш."
else
  echo "SmartumSwitch удалён. Настройки сохранены в ~/.config/smartum-switch (для удаления добавьте --purge)."
fi
