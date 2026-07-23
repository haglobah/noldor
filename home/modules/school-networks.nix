{ ... }:
{
  programs.ssh.matchBlocks."github.com" = {
    hostname = "ssh.github.com";
    port = 443;
    user = "git";
  };

  # sslh on the servers multiplexes 443 (see modules/sslh.nix).
  # Raw IPs dodge possible DNS filtering; the FortiGate only sees
  # an SSH handshake on 443, which it passes.
  programs.ssh.matchBlocks."formenos" = {
    hostname = "49.12.12.164";
    port = 443;
    user = "root";
  };

  programs.ssh.matchBlocks."orthanc" = {
    hostname = "91.99.217.220";
    port = 443;
    user = "root";
  };
}
