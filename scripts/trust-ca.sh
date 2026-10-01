#!/usr/bin/env bash
# Task E - make a client Mac trust the team CA, so https://app.<domain> shows
# no warning and curl works WITHOUT -k.  Run on every client Mac (Mac 1, Mac 4).
#
#   scripts/trust-ca.sh            download ca.crt from the edge, verify, trust it
#   scripts/trust-ca.sh remove     take it out of the trust store again
set -euo pipefail
source "$(dirname "$0")/common.sh"
mkdir -p "$TLS_DIR"
CA="$TLS_DIR/ca.crt"

if [ "${1:-}" = "remove" ]; then
  is_mac && run sudo security delete-certificate -c "${TEAM_NAME} Local Root CA" /Library/Keychains/System.keychain
  exit 0
fi

# Always fetch the CA that the edge is using RIGHT NOW (unless this machine is
# the edge itself, which has ca.key) - an old ca.crt from git would be wrong.
if [ ! -f "$TLS_DIR/ca.key" ]; then
  say "Downloading the CA certificate from the edge over plain HTTP"
  HP=""; [ "$HTTP_PORT" = "80" ] || HP=":$HTTP_PORT"
  run curl --noproxy "*" -fsS "http://app.${DOMAIN}${HP}/ca.crt" -o "$CA"
fi

say "Fingerprint of the CA we got - compare with the one printed on Mac 2:"
openssl x509 -in "$CA" -noout -subject -fingerprint -sha256
read -r -p "Does it match what Mac 2 shows? [y/N] " yn
[ "$yn" = "y" ] || [ "$yn" = "Y" ] || die "not trusting an unverified CA"

if is_mac; then
  run sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CA"
  ok "CA trusted in the System keychain (Safari/Chrome use this). Restart the browser."
else
  run sudo cp "$CA" /usr/local/share/ca-certificates/"${TEAM_ID}"-ca.crt && run sudo update-ca-certificates
fi

say "Test (note: no -k anywhere)"
curl_tls_args
run curl -sS "${CURL_TLS[@]}" -o /dev/null -w "HTTP %{http_code}  ssl_verify_result=%{ssl_verify_result} (0 = certificate trusted)\n" "$APP_URL/api/status"
