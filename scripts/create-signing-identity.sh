#!/bin/zsh
set -euo pipefail

# Creates the local code-signing identity release.sh signs with.
#
# Ad-hoc signing (`codesign --sign -`) gives a bundle an identity that IS its
# code hash, so every rebuild is a different application as far as macOS is
# concerned. Anything granted to the app personally — a Keychain item's access
# list, a TCC permission, a firewall exception — is granted to that one build
# and lost with the next. A signing certificate fixes that: the designated
# requirement names the certificate rather than the bytes, so it survives every
# rebuild.
#
# This certificate is self-signed and local. It is not a Developer ID, it does
# not satisfy Gatekeeper on anyone else's Mac, and it is not for distribution.
# It exists so this Mac can recognise its own builds as one continuous app.

NAME="${CREWLISTR_SIGNING_IDENTITY:-CrewListr Pro Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
DAYS=3650

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$NAME"; then
  echo "Signing identity already present: $NAME"
  security find-identity -v -p codesigning | grep -F "$NAME"
  exit 0
fi

WORK="$(mktemp -d)"
# The private key exists as a file only between openssl writing it and the
# Keychain taking ownership. Remove it on every exit path, including failure.
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CONFIG
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[dn]
CN = $NAME
O  = CrewListr Pro
C  = GR

[v3]
# A leaf that signs code and nothing else: not a CA, no key exchange, no
# server or client authentication. If it ever leaks it can do one thing.
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
CONFIG

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days "$DAYS" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

# -T /usr/bin/codesign puts codesign on the private key's access list, so
# signing never stops to ask. Nothing else on this Mac is granted the key.
security import "$WORK/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
security import "$WORK/cert.pem" -k "$KEYCHAIN"

# codesign will not build a chain to an untrusted root, so the certificate has
# to be trusted for code signing. User domain only: this asks for the login
# password in a system dialog and touches nothing outside this account.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo ""
security find-identity -v -p codesigning | grep -F "$NAME" || {
  echo "The identity was created but is not valid for code signing yet." >&2
  echo "Open Keychain Access, find '$NAME', and set Trust -> Code Signing to Always Trust." >&2
  exit 1
}
echo ""
echo "Created $NAME, valid for $DAYS days."
echo "release.sh now signs with it automatically."
