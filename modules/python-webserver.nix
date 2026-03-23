{ pkgs, ... }:
let
  webRoot = pkgs.writeTextDir "index.html" ''
    <!DOCTYPE html>
    <html>
    <head><title>noldor</title></head>
    <body>
      <h1>Hello from the local net</h1>
      <p>Served by Python on NixOS.</p>
    </body>
    </html>
  '';
in
{
  systemd.services.python-webserver = {
    description = "Simple Python HTTP server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python -m http.server 8888 --directory ${webRoot}";
      DynamicUser = true;
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 ];

  services.caddy = {
    enable = true;
    virtualHosts.":80" = {
      extraConfig = ''
        reverse_proxy 127.0.0.1:8888
      '';
    };
  };
}
