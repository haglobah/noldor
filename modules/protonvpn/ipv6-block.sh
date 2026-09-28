# NetworkManager dispatcher script: while the ProtonVPN profile is up, reject
# all IPv6 traffic except loopback and the tunnel. Proton's config is IPv4
# only, so without this IPv6 would bypass the VPN on dual-stack networks.
# Reject (not drop) lets apps fall back to IPv4 at once.
set -uo pipefail

interface=$1
action=$2
table=protonvpn-ipv6-block

[ "${CONNECTION_ID:-}" = ProtonVPN ] || exit 0

case "$action" in
  up)
    # One nft run is atomic: the stale table goes and the new one lands
    # together, so there is no window without the block.
    if ! nft -f - <<EOF; then
table ip6 $table
destroy table ip6 $table
table ip6 $table {
  chain output {
    type filter hook output priority 0; policy accept;
    oifname "lo" accept
    oifname "$interface" accept
    reject with icmpv6 admin-prohibited
  }
  chain forward {
    type filter hook forward priority 0; policy accept;
    oifname "$interface" accept
    reject with icmpv6 admin-prohibited
  }
}
EOF
      echo "ProtonVPN: failed to block IPv6 outside the tunnel" >&2
      exit 1
    fi
    ;;
  down)
    nft destroy table ip6 "$table"
    ;;
esac
