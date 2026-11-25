#!/usr/bin/env bash
# Build SmartumSwitch.app on a Mac with the Xcode Command Line Tools (free; Xcode itself is not needed).
# Nothing is installed or changed outside this folder: the result is macos/_app/SmartumSwitch.app.
# Signing: a local self-signed cert in a dedicated keychain (permissions survive rebuilds).
# Falls back to ad-hoc ("codesign -s -") if the identity cannot be created without a password prompt.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"; CORE="$ROOT/core"
APP="_app/SmartumSwitch.app"; OBJ="_obj"
ARCH="${ARCH:-$(uname -m)}"            # x86_64 or arm64
TARGET="$ARCH-apple-macos13.0"

if ! xcrun --find swiftc >/dev/null 2>&1 || ! xcrun --find clang++ >/dev/null 2>&1; then
  echo "Нет Command Line Tools (swiftc/clang++). Их ставит сам пользователь: xcode-select --install (бесплатно, ~1–2 ГБ)."
  exit 1
fi
echo "swiftc: $(xcrun swiftc --version 2>&1 | head -1)"
echo "target: $TARGET"

# 1. hunspell (vendor/hunspell, MPL/LGPL) — the same spell checker as on Linux and Windows
mkdir -p "$OBJ/$ARCH"
for f in vendor/hunspell/*.cxx; do
  o="$OBJ/$ARCH/$(basename "${f%.cxx}").o"
  if [ ! -f "$o" ] || [ "$f" -nt "$o" ]; then
    xcrun clang++ -target "$TARGET" -O2 -std=c++11 -DHUNSPELL_STATIC -w -c "$f" -o "$o"
  fi
done

# 2. the app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/data" "$APP/Contents/Resources/dict" "$APP/Contents/Resources/tests"
xcrun swiftc -target "$TARGET" -O -swift-version 5 -module-name SmartumSwitch \
  -import-objc-header Sources/Bridge.h Sources/*.swift "$OBJ/$ARCH"/*.o -lc++ \
  -framework Cocoa -framework Carbon -framework ApplicationServices -framework ServiceManagement \
  -o "$APP/Contents/MacOS/SmartumSwitch"

# 3. resources: shared core data, dictionaries (+ their licenses), tests
cp Resources/Info.plist "$APP/Contents/Info.plist"
# App icon: build official .icns with iconutil when possible, else use the prebuilt file
ICONSET=Resources/AppIcon.iconset
if [[ -f Resources/AppIcon.png ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
fi
if [[ -d "$ICONSET" ]] && command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
elif [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
cp "$CORE"/data/*.json "$APP/Contents/Resources/data/"
cp "$CORE"/dict/*.aff "$CORE"/dict/*.dic "$CORE"/dict/LICENSE* "$APP/Contents/Resources/dict/"
cp "$CORE/tests/cases.json" "$APP/Contents/Resources/tests/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp vendor/hunspell/COPYING.MPL "$APP/Contents/Resources/LICENSE.hunspell.MPL.txt"

# 4. Sign: stable local identity if available (TCC permissions persist); otherwise ad-hoc
SIGN_SH="$(pwd)/signing/ensure-identity.sh"
LOGIN="$HOME/Library/Keychains/login.keychain-db"
restore_keychains() { security list-keychains -d user -s "$LOGIN" >/dev/null 2>&1 || true; }
if [[ -x "$SIGN_SH" ]] && ID_LINE=$("$SIGN_SH" 2>/tmp/smartum-sign.err); then
  SIGN_KC=$(printf '%s\n' "$ID_LINE" | awk -F '\t' '{print $2}')
  SIGN_NAME=$(printf '%s\n' "$ID_LINE" | awk -F '\t' '{print $3}')
  security unlock-keychain -p "$(cat "$HOME/Library/Application Support/SmartumSwitch/signing/keychain.pass")" "$SIGN_KC" >/dev/null
  # codesign only sees the identity if the keychain is on the user search list
  security list-keychains -d user -s "$SIGN_KC" "$LOGIN" >/dev/null
  if codesign --force --sign "$SIGN_NAME" --keychain "$SIGN_KC" --identifier com.smartum.SmartumSwitch "$APP"; then
    restore_keychains
    echo "подпись: локальный сертификат $SIGN_NAME (постоянная)"
  else
    restore_keychains
    echo "не удалось подписать постоянным сертификатом, пробую ad-hoc"
    codesign --force --sign - --identifier com.smartum.SmartumSwitch "$APP"
    echo "подпись: ad-hoc (разрешения после пересборки нужно будет выдать заново)"
  fi
else
  restore_keychains
  codesign --force --sign - --identifier com.smartum.SmartumSwitch "$APP"
  echo "подпись: ad-hoc (разрешения после пересборки нужно будет выдать заново)"
  if [[ -s /tmp/smartum-sign.err ]]; then echo "(не удалось создать постоянную подпись: см. журнал сборки)"; fi
fi

# 5. core tests (no permissions needed)
"$APP/Contents/MacOS/SmartumSwitch" --selftest
echo
echo "Готово: $(pwd)/$APP"
