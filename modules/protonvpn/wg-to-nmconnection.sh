# Convert a Proton WireGuard config (wg-quick format, on stdin) into a
# NetworkManager keyfile (on stdout) for a full tunnel named "ProtonVPN".
# Fails without output when a required field is missing.
set -euo pipefail

conf=$(tr -d '\r')

# field <name>: value of the first "<name> = value" line, or empty.
field() {
  printf '%s\n' "$conf" | sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" | head -n 1
}

# split <list>: comma-separated list to one trimmed item per line.
split() {
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true
}

private_key=$(field PrivateKey)
public_key=$(field PublicKey)
endpoint=$(field Endpoint)
addresses=$(split "$(field Address)")
dns=$(split "$(field DNS)")
allowed_ips=$(split "$(field AllowedIPs)")
keepalive=$(field PersistentKeepalive)

address4=$(printf '%s\n' "$addresses" | grep -v ':' | head -n 1 || true)
address6=$(printf '%s\n' "$addresses" | grep ':' | head -n 1 || true)
dns4=$(printf '%s\n' "$dns" | grep -v ':' || true)
dns6=$(printf '%s\n' "$dns" | grep ':' || true)

missing=()
[ -n "$private_key" ] || missing+=(PrivateKey)
[ -n "$public_key" ] || missing+=(PublicKey)
[ -n "$endpoint" ] || missing+=(Endpoint)
[ -n "$address4" ] || missing+=("Address (IPv4)")
if [ ${#missing[@]} -gt 0 ]; then
  echo "Proton WireGuard config lacks: ${missing[*]}" >&2
  exit 1
fi

# join: lines on stdin to NetworkManager's "a;b;" list form.
join() { tr '\n' ';' | sed 's/;;*/;/g; s/^;//'; }

cat <<EOF
[connection]
id=ProtonVPN
uuid=3c1f7a52-6d0e-4b8a-9f43-5e2d8c7a1b90
type=wireguard
interface-name=proton0
autoconnect=false

[wireguard]
private-key=$private_key

[wireguard-peer.$public_key]
endpoint=$endpoint
allowed-ips=$(printf '%s\n' "${allowed_ips:-0.0.0.0/0}" | join)
${keepalive:+persistent-keepalive=$keepalive}

[ipv4]
method=manual
address1=$address4
dns=$(printf '%s\n' "$dns4" | join)
dns-search=~.;
dns-priority=-50
EOF

if [ -n "$address6" ]; then
  cat <<EOF

[ipv6]
method=manual
address1=$address6
dns=$(printf '%s\n' "$dns6" | join)
dns-search=~.;
dns-priority=-50
EOF
else
  printf '\n[ipv6]\nmethod=disabled\n'
fi
