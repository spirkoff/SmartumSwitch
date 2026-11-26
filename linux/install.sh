#!/usr/bin/env bash
# SmartumSwitch universal Linux installer for official release v0.2.0.
# Free, open-source (MIT), no ads, no telemetry, no bundled third-party software.
#
# One-command install:
#   curl -fsSL https://raw.githubusercontent.com/spirkoff/SmartumSwitch/main/linux/install.sh | bash
#
# Options:
#   --no-hotkey     do not register the Pause hotkey on GNOME/Pantheon
#   --no-auto       do not configure autostart
#   --no-sudo       user-space install only (do not run sudo for packages or udev)
#   --uninstall     uninstall SmartumSwitch
#   --purge         (with --uninstall) also remove ~/.config/smartum-switch and cache
set -euo pipefail

VERSION="v0.2.0"
RELEASE_URL="${SMARTUM_RELEASE_URL:-https://github.com/spirkoff/SmartumSwitch/archive/refs/tags/v0.2.0.tar.gz}"
ARCHIVE_SHA256="fdee07fd0213b634e3a80eafa4dc3fcdc9086adfe9211ca567091ed7a9828771"
BIN_SHA256="a2f5df2fc1fa314b948f7f5f65183a03b93ef6cd9e9de659aa3158b4d2ab2ca7"
SERVICE_SHA256="8d6c47cf20616a69cacb895ba066d535bbd20b2ec78fc7256d4606337e9a32ff"
UDEV_SHA256="50c48920b9518a809f55b9a7386cc668a0e4e23a0e1c522d96831810f91ee42f"

HOTKEY=1
AUTO=1
NO_SUDO=0
DO_UNINSTALL=0
PURGE=0

for a in "$@"; do
  case "$a" in
    --no-hotkey) HOTKEY=0 ;;
    --no-auto) AUTO=0 ;;
    --no-sudo) NO_SUDO=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    --purge) PURGE=1 ;;
    -h|--help)
      cat <<'USAGE'
SmartumSwitch v0.2.0 — установщик для Linux (MIT, без рекламы и лишнего ПО)
Использование:
  curl -fsSL https://raw.githubusercontent.com/spirkoff/SmartumSwitch/main/linux/install.sh | bash
  install.sh [--no-hotkey] [--no-auto] [--no-sudo] [--uninstall [--purge]]

Параметры:
  --no-hotkey   не добавлять горячую клавишу Pause в GNOME/Pantheon
  --no-auto     не добавлять в автозапуск
  --no-sudo     ставить только в каталог пользователя (~/.local), без sudo
  --uninstall   удалить SmartumSwitch (с --purge удалит и ~/.config/smartum-switch)
USAGE
      exit 0
      ;;
    *) echo "Неизвестный параметр: $a" >&2; exit 1 ;;
  esac
done

info() { printf '==> %s\n' "$*"; }
ok()   { printf '  [ok] %s\n' "$*"; }
warn() { printf '  [!] %s\n' "$*" >&2; }
err()  { printf '  [x] %s\n' "$*" >&2; }

can_priv() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if [ "$NO_SUDO" = 1 ]; then
    return 1
  fi
  command -v sudo >/dev/null 2>&1 || return 1
  if sudo -n true >/dev/null 2>&1; then
    return 0
  fi
  [ -t 0 ] || { (: </dev/tty) 2>/dev/null; }
}

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

file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
  else
    err "Не найден sha256sum, shasum или python3 для проверки SHA-256."
    return 1
  fi
}

verify_sha256() {
  local file="$1" expected="$2" label="$3" actual
  actual="$(file_sha256 "$file")"
  if [ "$actual" != "$expected" ]; then
    err "Ошибка проверки SHA-256 для $label!"
    err "  ожидалось: $expected"
    err "  получено:  $actual"
    return 1
  fi
  ok "SHA-256 верный: $label"
}

write_uninstaller() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  cat <<'UNINST_EOF' > "$target"
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
UNINST_EOF
  chmod 755 "$target"
}

if [ "$DO_UNINSTALL" = 1 ]; then
  TMP_UNINST="$(mktemp)"
  trap 'rm -f "$TMP_UNINST"' EXIT
  write_uninstaller "$TMP_UNINST"
  ARGS=()
  [ "$PURGE" = 1 ] && ARGS+=(--purge)
  [ "$NO_SUDO" = 1 ] && ARGS+=(--no-sudo)
  exec bash "$TMP_UNINST" "${ARGS[@]}"
fi

if [ "$(id -u)" -eq 0 ]; then
  if [ -n "${SUDO_USER:-}" ]; then
    err "Не запускайте установщик через sudo. Запускайте обычным пользователем (sudo запросится только при необходимости)."
    exit 1
  fi
  if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && [ "${SMARTUM_ALLOW_ROOT:-0}" != 1 ]; then
    err "Запускайте от обычного пользователя (без root), чтобы программа и автозапуск установились в ваш профиль."
    exit 1
  fi
fi

# ---------- Определение архитектуры и дистрибутива ----------
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH_DESC="x86_64 (64-bit)" ;;
  aarch64|arm64) ARCH_DESC="aarch64 (ARM64)" ;;
  i386|i686|armv7l|riscv64)
    ARCH_DESC="$ARCH"
    warn "Архитектура $ARCH не проходила отдельную проверку; продолжаем (Python + системный libhunspell)."
    ;;
  *)
    warn "Неизвестная архитектура: $ARCH; продолжаем установку."
    ARCH_DESC="$ARCH"
    ;;
esac

OS_RELEASE="${SMARTUM_OS_RELEASE:-/etc/os-release}"
OS_ID=""
OS_ID_LIKE=""
OS_PRETTY="Linux"
if [ -r "$OS_RELEASE" ]; then
  OS_ID="$(awk -F= '$1=="ID"{gsub(/"/,"",$2); print tolower($2)}' "$OS_RELEASE" | head -n1)"
  OS_ID_LIKE="$(awk -F= '$1=="ID_LIKE"{gsub(/"/,"",$2); print tolower($2)}' "$OS_RELEASE" | head -n1)"
  OS_PRETTY="$(awk -F= '$1=="PRETTY_NAME"{gsub(/"/,"",$2); print $2}' "$OS_RELEASE" | head -n1)"
  [ -z "$OS_PRETTY" ] && OS_PRETTY="${OS_ID:-Linux}"
fi

PKG_MGR=""
case " $OS_ID $OS_ID_LIKE " in
  *" debian "*|*" ubuntu "*|*" elementary "*|*" linuxmint "*|*" pop "*|*" zorin "*|*" kali "*|*" neon "*|*" raspbian "*)
    PKG_MGR="apt" ;;
  *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" nobara "*|*" bazzite "*)
    PKG_MGR="dnf" ;;
  *" arch "*|*" manjaro "*|*" endeavouros "*|*" cachyos "*|*" garuda "*)
    PKG_MGR="pacman" ;;
  *" opensuse"*|*" suse "*|*" sles "*)
    PKG_MGR="zypper" ;;
  *" alpine "*)
    PKG_MGR="apk" ;;
esac

if [ -z "$PKG_MGR" ]; then
  if command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt"
  elif command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"
  elif command -v yum >/dev/null 2>&1; then PKG_MGR="yum"
  elif command -v pacman >/dev/null 2>&1; then PKG_MGR="pacman"
  elif command -v zypper >/dev/null 2>&1; then PKG_MGR="zypper"
  elif command -v apk >/dev/null 2>&1; then PKG_MGR="apk"
  fi
fi

info "Система: $OS_PRETTY | архитектура: $ARCH_DESC | менеджер пакетов: ${PKG_MGR:-не определён}"

# ---------- Скачивание и проверка SHA-256 официального релиза v0.2.0 ----------
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
ARCHIVE="$TMPDIR/SmartumSwitch-${VERSION}.tar.gz"

info "Скачивание официального релиза SmartumSwitch $VERSION с GitHub"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --retry 2 --connect-timeout 15 "$RELEASE_URL" -o "$ARCHIVE"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$ARCHIVE" "$RELEASE_URL"
else
  err "Не найден curl или wget. Установите curl и повторите команду."
  exit 1
fi

verify_sha256 "$ARCHIVE" "$ARCHIVE_SHA256" "SmartumSwitch-${VERSION}.tar.gz"

info "Распаковка и проверка файлов релиза"
if command -v tar >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1; then
  tar -xzf "$ARCHIVE" -C "$TMPDIR"
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import inspect,tarfile,sys; tf=tarfile.open(sys.argv[1],"r:gz"); kw={"filter":"data"} if "filter" in inspect.signature(tf.extractall).parameters else {}; tf.extractall(sys.argv[2], **kw)' "$ARCHIVE" "$TMPDIR"
else
  err "Не найден tar или python3 для распаковки архива."
  exit 1
fi

SRC="$TMPDIR/SmartumSwitch-0.2.0"
verify_sha256 "$SRC/linux/smartum-switch" "$BIN_SHA256" "linux/smartum-switch"
verify_sha256 "$SRC/linux/systemd/smartum-switch.service" "$SERVICE_SHA256" "linux/systemd/smartum-switch.service"
verify_sha256 "$SRC/linux/udev/70-smartum-switch.rules" "$UDEV_SHA256" "linux/udev/70-smartum-switch.rules"

# ---------- Проверка системных зависимостей ----------
MISSING_DESC=()
check_deps() {
  MISSING_DESC=()
  if ! command -v python3 >/dev/null 2>&1; then
    MISSING_DESC+=("python3")
  else
    python3 -c "import evdev" >/dev/null 2>&1 || MISSING_DESC+=("python3-evdev")
    python3 -c 'import ctypes; ctypes.CDLL("libhunspell-1.7.so.0")' >/dev/null 2>&1 || MISSING_DESC+=("libhunspell-1.7")
  fi
  [ -f /usr/share/hunspell/ru_RU.aff ] && [ -f /usr/share/hunspell/ru_RU.dic ] || MISSING_DESC+=("hunspell-ru")
  [ -f /usr/share/hunspell/en_US.aff ] && [ -f /usr/share/hunspell/en_US.dic ] || MISSING_DESC+=("hunspell-en-US")
  command -v wl-copy >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1 || MISSING_DESC+=("wl-clipboard")
  command -v notify-send >/dev/null 2>&1 || MISSING_DESC+=("notify-send")
  [ "${#MISSING_DESC[@]}" -eq 0 ]
}

pkg_hint() {
  case "$PKG_MGR" in
    apt)
      echo "sudo apt-get update && sudo apt-get install -y python3 python3-evdev wl-clipboard libhunspell-1.7-0 hunspell-ru hunspell-en-us libnotify-bin" ;;
    dnf|yum)
      echo "sudo $PKG_MGR install -y python3 python3-evdev wl-clipboard hunspell hunspell-ru hunspell-en-US libnotify" ;;
    pacman)
      echo "sudo pacman -Sy --needed python python-evdev wl-clipboard hunspell hunspell-en_us libnotify" ;;
    zypper)
      echo "sudo zypper install -y python3 python3-evdev wl-clipboard hunspell myspell-ru_RU myspell-en_US libnotify-tools" ;;
    apk)
      echo "sudo apk add python3 py3-evdev wl-clipboard hunspell libnotify" ;;
    *)
      echo "Установите пакеты: python3, python3-evdev, libhunspell-1.7, словари hunspell ru_RU и en_US, wl-clipboard, libnotify (notify-send)." ;;
  esac
}

info "Проверка системных зависимостей"
if check_deps; then
  ok "Все зависимости уже установлены (sudo для пакетов не требуется)."
else
  warn "Не хватает зависимостей: ${MISSING_DESC[*]}"
  if can_priv && [ -n "$PKG_MGR" ]; then
    info "Установка минимально необходимых пакетов ($PKG_MGR)"
    case "$PKG_MGR" in
      apt)
        run_priv env DEBIAN_FRONTEND=noninteractive apt-get update -qq
        run_priv env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
          python3 python3-evdev wl-clipboard libhunspell-1.7-0 hunspell-ru hunspell-en-us libnotify-bin
        ;;
      dnf)
        run_priv dnf install -y python3 python3-evdev wl-clipboard hunspell hunspell-ru hunspell-en-US libnotify
        ;;
      yum)
        run_priv yum install -y python3 python3-evdev wl-clipboard hunspell hunspell-ru hunspell-en-US libnotify
        ;;
      pacman)
        run_priv pacman -Sy --needed --noconfirm python python-evdev wl-clipboard hunspell hunspell-en_us libnotify
        ;;
      zypper)
        run_priv zypper --non-interactive install python3 python3-evdev wl-clipboard hunspell myspell-ru_RU myspell-en_US libnotify-tools
        ;;
      apk)
        run_priv apk add --no-cache python3 py3-evdev wl-clipboard hunspell libnotify
        ;;
    esac
    # Если в системе (например, Arch/Alpine) нет словарей в /usr/share/hunspell/, ставим словари из проверенного архива v0.2.0
    if [ ! -f /usr/share/hunspell/ru_RU.aff ] && [ -f "$SRC/core/dict/ru_RU.aff" ]; then
      run_priv install -D -m 644 "$SRC/core/dict/ru_RU.aff" /usr/share/hunspell/ru_RU.aff
      run_priv install -D -m 644 "$SRC/core/dict/ru_RU.dic" /usr/share/hunspell/ru_RU.dic
    fi
    if [ ! -f /usr/share/hunspell/en_US.aff ] && [ -f "$SRC/core/dict/en_US.aff" ]; then
      run_priv install -D -m 644 "$SRC/core/dict/en_US.aff" /usr/share/hunspell/en_US.aff
      run_priv install -D -m 644 "$SRC/core/dict/en_US.dic" /usr/share/hunspell/en_US.dic
    fi
    if check_deps; then
      ok "Все зависимости установлены."
    else
      warn "Часть зависимостей всё ещё не найдена: ${MISSING_DESC[*]}"
    fi
  else
    warn "Пропуск установки пакетов (--no-sudo или нет прав sudo)."
    warn "Установите пакеты вручную: $(pkg_hint)"
  fi
fi

# ---------- Установка программы в пользовательский каталог (без sudo) ----------
info "Установка SmartumSwitch в $HOME/.local/bin/smartum-switch (без sudo)"
install -D -m 755 "$SRC/linux/smartum-switch" "$HOME/.local/bin/smartum-switch"
write_uninstaller "$HOME/.local/share/smartum-switch/uninstall.sh"
ok "Установлено: $HOME/.local/bin/smartum-switch"
ok "Деинсталлятор: $HOME/.local/share/smartum-switch/uninstall.sh"

# ---------- Правило udev (sudo только если правило отсутствует или отличается) ----------
UDEV_DST="/etc/udev/rules.d/70-smartum-switch.rules"
if [ -f "$UDEV_DST" ] && [ "$(file_sha256 "$UDEV_DST")" = "$UDEV_SHA256" ]; then
  ok "Правило udev уже установлено и актуально ($UDEV_DST)"
elif can_priv; then
  info "Установка правила udev ($UDEV_DST)"
  run_priv install -D -m 644 "$SRC/linux/udev/70-smartum-switch.rules" "$UDEV_DST"
  run_priv udevadm control --reload 2>/dev/null || true
  run_priv udevadm trigger --name-match=uinput --action=add 2>/dev/null || true
  run_priv udevadm trigger --subsystem-match=input --action=change 2>/dev/null || true
  ok "Правило udev установлено."
else
  warn "Правило udev не установлено (требуются права sudo для /dev/uinput и evdev)."
  warn "Выполните позже: curl -fsSL https://raw.githubusercontent.com/spirkoff/SmartumSwitch/main/linux/udev/70-smartum-switch.rules | sudo tee $UDEV_DST >/dev/null && sudo udevadm control --reload"
fi

# ---------- Автозапуск (без sudo) ----------
if [ "$AUTO" = 1 ]; then
  info "Настройка автозапуска (без sudo)"
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    install -D -m 644 "$SRC/linux/systemd/smartum-switch.service" "$HOME/.config/systemd/user/smartum-switch.service"
    rm -f "$HOME/.config/autostart/smartum-switch.desktop"
    if systemctl --user show-environment >/dev/null 2>&1; then
      systemctl --user daemon-reload
      systemctl --user enable smartum-switch.service
      systemctl --user restart smartum-switch.service || echo "   (служба запустится при следующем входе в систему)"
      ok "Включена пользовательская служба systemd: smartum-switch.service"
    else
      mkdir -p "$HOME/.config/systemd/user/graphical-session.target.wants"
      ln -sf ../smartum-switch.service "$HOME/.config/systemd/user/graphical-session.target.wants/smartum-switch.service"
      ok "Служба systemd добавлена в автозапуск (запустится при входе в графическую сессию)."
    fi
  else
    mkdir -p "$HOME/.config/autostart"
    cat <<DESKTOP_EOF > "$HOME/.config/autostart/smartum-switch.desktop"
[Desktop Entry]
Type=Application
Name=SmartumSwitch
Comment=Автопереключатель раскладки QWERTY <-> ЙЦУКЕН
Exec=$HOME/.local/bin/smartum-switch daemon
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP_EOF
    ok "Добавлен XDG-автозапуск: $HOME/.config/autostart/smartum-switch.desktop"
  fi
fi

# ---------- Горячая клавиша Pause (GNOME / Pantheon, без sudo) ----------
if [ "$HOTKEY" = 1 ] \
  && command -v gsettings >/dev/null 2>&1 \
  && command -v python3 >/dev/null 2>&1 \
  && { [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; } \
  && gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.settings-daemon.plugins.media-keys'; then
  info "Настройка клавиши Pause -> smartum-switch"
  KP=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/smartum-switch/
  LIST=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "@as []")
  NEW=$(python3 -c "import ast,sys; l=sys.argv[1].replace('@as ',''); l=ast.literal_eval(l); p=sys.argv[2]; l=l+[p] if p not in l else l; print(str(l))" "$LIST" "$KP")
  gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW"
  S=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KP
  gsettings set "$S" name 'SmartumSwitch: исправить раскладку'
  gsettings set "$S" command "$HOME/.local/bin/smartum-switch"
  gsettings set "$S" binding 'Pause'
  ok "Клавиша Pause привязана."
fi

echo
echo "Готово! SmartumSwitch $VERSION установлен в $HOME/.local/bin/smartum-switch."
case ":${PATH:-}:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Примечание: добавьте ~/.local/bin в PATH (или перезайдите в сессию), чтобы вызывать smartum-switch без полного пути." ;;
esac
echo "Клавиши: Pause — исправить выделенное/слово, Shift+Pause — вкл/выкл автоисправление."
echo "Исключения: ~/.config/smartum-switch/exceptions.txt | Свои слова: ~/.config/smartum-switch/words.txt"
echo "Удаление одной командой: $HOME/.local/share/smartum-switch/uninstall.sh"
