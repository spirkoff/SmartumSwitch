#!/usr/bin/env bash
# Create a local self-signed code-signing identity (root CA + leaf) in a dedicated
# keychain so TCC permissions survive rebuilds. No Apple developer account.
# Does not use the login keychain and does not keep this keychain in the user's
# default search list. Never prompts for a password. If the cert exists but is
# not trusted, prints SIGN_FAIL untrusted and exits 1 (does not create another).
#
# Usage:
#   ensure-identity.sh          # create/import if needed; SIGN_OK or SIGN_FAIL
#   ensure-identity.sh --trust  # show the system trust dialog for the CA (admin)
set -euo pipefail
DIR="${SMARTUM_SIGN_DIR:-$HOME/Library/Application Support/SmartumSwitch/signing}"
KC="$DIR/SmartumSwitch.keychain-db"
PASS="$DIR/keychain.pass"
NAME="SmartumSwitch"
CA_NAME="SmartumSwitch CA"
CA_PEM="$DIR/ca.pem"
LEAF_PEM="$DIR/codesign.pem"
LEAF_P12="$DIR/codesign.p12"
P12_PASS_FILE="$DIR/p12.pass"
mkdir -p "$DIR"
chmod 700 "$DIR"

OLD_LIST=()
while IFS= read -r line; do
  line=${line//\"/}
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n "$line" ]] && OLD_LIST+=("$line")
done < <(security list-keychains -d user)
restore_list() { security list-keychains -d user -s "${OLD_LIST[@]}" >/dev/null 2>&1 || true; }

if [[ ! -f "$PASS" ]]; then
  /usr/bin/openssl rand -base64 24 > "$PASS"
  chmod 600 "$PASS"
fi
KP=$(cat "$PASS")

valid_identity() {
  security unlock-keychain -p "$KP" "$KC" >/dev/null 2>&1 || return 1
  security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -q "$NAME"
}

ensure_keychain() {
  if [[ ! -f "$KC" ]]; then
    security create-keychain -p "$KP" "$KC"
    restore_list
    security set-keychain-settings -u "$KC"
  fi
  restore_list
  security unlock-keychain -p "$KP" "$KC"
  security set-keychain-settings -u "$KC"
}

generate_certs() {
  # Persistent CA + leaf, created once. Later runs reuse these files so the
  # designated requirement stays the same across rebuilds and keychain resets.
  if [[ -f "$CA_PEM" && -f "$LEAF_PEM" && -f "$LEAF_P12" && -f "$P12_PASS_FILE" ]]; then
    return 0
  fi
  TMP=$(mktemp -d /tmp/smartum-sign.XXXXXX)
  trap 'rm -rf "$TMP"' RETURN
  cat > "$TMP/ca.cnf" << 'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = SmartumSwitch CA
O = smARTum
[v3]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
CNF
  cat > "$TMP/leaf.cnf" << 'CNF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = SmartumSwitch
O = smARTum
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
CNF
  /usr/bin/openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 \
    -keyout "$TMP/ca.key" -out "$TMP/ca.pem" -config "$TMP/ca.cnf" 2>/dev/null
  /usr/bin/openssl req -new -nodes -newkey rsa:2048 \
    -keyout "$TMP/leaf.key" -out "$TMP/leaf.csr" -config "$TMP/leaf.cnf" 2>/dev/null
  /usr/bin/openssl x509 -req -in "$TMP/leaf.csr" -CA "$TMP/ca.pem" -CAkey "$TMP/ca.key" \
    -CAcreateserial -out "$TMP/leaf.pem" -days 3650 -extfile "$TMP/leaf.cnf" -extensions v3 2>/dev/null
  /usr/bin/openssl rand -base64 18 > "$P12_PASS_FILE"
  chmod 600 "$P12_PASS_FILE"
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/leaf.key" -in "$TMP/leaf.pem" \
    -certfile "$TMP/ca.pem" -out "$TMP/leaf.p12" -passout "pass:$(cat "$P12_PASS_FILE")" \
    -name "$NAME" 2>/dev/null
  install -m 600 "$TMP/ca.pem" "$CA_PEM"
  install -m 600 "$TMP/leaf.pem" "$LEAF_PEM"
  install -m 600 "$TMP/leaf.p12" "$LEAF_P12"
  # Keep the CA key too, in case the leaf ever needs to be reissued under the same CA.
  install -m 600 "$TMP/ca.key" "$DIR/ca.key"
  trap - RETURN
  rm -rf "$TMP"
}

fp_sha1() {
  /usr/bin/openssl x509 -noout -fingerprint -sha1 2>/dev/null | awk -F= '{print $NF}' | tr -d ': '
}
leaf_already_in_keychain() {
  local have want
  have=$(security find-certificate -c "$NAME" -p "$KC" 2>/dev/null | fp_sha1)
  want=$(fp_sha1 < "$LEAF_PEM")
  [[ -n "$have" && "$have" == "$want" ]]
}
import_certs() {
  ensure_keychain
  if ! leaf_already_in_keychain; then
    security import "$CA_PEM" -k "$KC" -A >/dev/null 2>&1 || true
    security import "$LEAF_P12" -k "$KC" -P "$(cat "$P12_PASS_FILE")" -A \
      -T /usr/bin/codesign -T /usr/bin/security >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KP" "$KC" >/dev/null
  fi
  restore_list
}

trust_ca() {
  if [[ ! -f "$CA_PEM" ]]; then
    echo "SIGN_FAIL no-ca" >&2
    exit 1
  fi
  # -d: admin trust store (system dialog, user enters the password).
  # Do not wrap in sudo: that would ask for a password in the terminal.
  security add-trusted-cert -d -r trustRoot -p basic -p codeSign \
    -k /Library/Keychains/System.keychain "$CA_PEM"
}

# --- main ---
if [[ "${1:-}" == "--trust" ]]; then
  generate_certs
  import_certs
  trust_ca
  if valid_identity; then
    printf "SIGN_OK\t%s\t%s\n" "$KC" "$NAME"
    exit 0
  fi
  echo "SIGN_FAIL untrusted"
  exit 1
fi

generate_certs
import_certs

if valid_identity; then
  printf "SIGN_OK\t%s\t%s\n" "$KC" "$NAME"
  exit 0
fi
echo "SIGN_FAIL untrusted"
exit 1
