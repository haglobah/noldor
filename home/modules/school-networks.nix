{ ... }:
{
  # Without enable = true, home-manager silently ignores the settings
  # below and never generates ~/.ssh/config.
  programs.ssh.enable = true;

  # The old implicit defaults (ForwardAgent no, Compression no, ...) all
  # match OpenSSH's built-in defaults, so no settings."*" block is needed.
  programs.ssh.enableDefaultConfig = false;

  programs.ssh.settings."github.com" = {
    HostName = "ssh.github.com";
    Port = 443;
    User = "git";
  };

  # sslh on the servers multiplexes 443 (see modules/sslh.nix).
  # Raw IPs dodge possible DNS filtering; the FortiGate only sees
  # an SSH handshake on 443, which it passes.
  programs.ssh.settings."formenos" = {
    HostName = "49.12.12.164";
    Port = 443;
    User = "root";
  };

  programs.ssh.settings."orthanc" = {
    HostName = "91.99.217.220";
    Port = 443;
    User = "root";
  };
}
