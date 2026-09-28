# Toggle the declarative "ProtonVPN" NetworkManager profile
# (modules/protonvpn.nix). Connections made by the Proton app have other
# names and are left alone.
set -uo pipefail

name=ProtonVPN

if nmcli -g NAME connection show --active | grep -qxF "$name"; then
  action=down
else
  action=up
fi

if ! output=$(nmcli connection "$action" id "$name" 2>&1); then
  notify-send --icon=network-vpn-symbolic "ProtonVPN $action failed" "$output"
  echo "$output" >&2
  exit 1
fi
