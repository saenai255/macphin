#!/bin/zsh
# Creates a stable self-signed code signing identity so macOS privacy permissions survive rebuilds.
set -euo pipefail

NAME="Macphin Local Signing"
KEYCHAIN="$HOME/Library/Keychains/macphin-signing.keychain-db"
# Only guards this dedicated keychain, which holds nothing but the local signing key.
PASSWORD="macphin-local-signing"

if [[ -f "$KEYCHAIN" ]] && security find-identity -p codesigning "$KEYCHAIN" | grep -q "$NAME"; then
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $NAME
[codesign]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" -extensions codesign \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -passout pass:"$PASSWORD" -out "$WORK/identity.p12"

[[ -f "$KEYCHAIN" ]] || security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
echo "Created signing identity “$NAME” in $KEYCHAIN"
