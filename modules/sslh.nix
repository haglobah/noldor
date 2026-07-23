{ ... }:
{
  # Share port 443 between sshd and Caddy. School networks (FortiGate)
  # block outbound 22 but pass raw SSH on 443, so sslh listens on 443,
  # probes the first client bytes, and routes SSH to sshd and TLS to
  # Caddy on its moved-aside https port.
  services.sslh = {
    enable = true;
    settings = {
      # OpenSSH clients send their banner immediately; on-timeout only
      # catches clients that wait for the server banner first.
      on-timeout = "ssh";
      protocols = [
        {
          name = "ssh";
          host = "localhost";
          port = "22";
          service = "ssh";
        }
        {
          name = "tls";
          host = "localhost";
          port = "4443";
        }
      ];
    };
  };

  services.caddy = {
    # Externally still 443, via sslh. TLS-ALPN ACME challenges keep
    # working because sslh forwards them to Caddy like any other TLS.
    httpsPort = 4443;
    # Without this, http:// visitors would be redirected to the
    # unreachable https://<host>:4443. https:// URLs are unaffected.
    globalConfig = ''
      auto_https disable_redirects
    '';
  };
}
