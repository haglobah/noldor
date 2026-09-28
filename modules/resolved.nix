# systemd-resolved settings shared by all machines.
{
  # LLMNR: nothing here answers it, and resolved waits ~7s for it on every
  # reverse lookup of an on-link address (docker0 is 172.17/16, which some
  # ISPs use for routers), so `traceroute` stalls. Any LAN host can also
  # spoof LLMNR answers. mDNS (.local) stays on.
  services.resolved.settings.Resolve.LLMNR = false;
}
