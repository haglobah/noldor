# Links API worker (media-inbox's nixosModules.worker), moved off Cloudflare
# Workers once the free quota ran out. Vars mirror worker/wrangler.toml.
{ config, pkgs, ... }:
let
  secrets = config.clan.core.vars.generators.links-worker;
in
{
  # The Instant token and Resend key come from their dashboards (Cloudflare
  # secrets can't be read back). Minted here: the Telegram webhook secret
  # (register it with setWebhook at cutover) and the web push VAPID pair,
  # which Cloudflare never had. Regenerating the pair makes every device
  # re-enable push.
  clan.core.vars.generators.links-worker = {
    files."env" = { };
    files."telegram_webhook_secret" = { };
    files."vapid_public_key".secret = false;
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    prompts."instant-admin-token" = {
      type = "hidden";
      description = "Instant admin token for the Links app (instantdb.com dashboard)";
    };
    prompts."resend-api-key" = {
      type = "hidden";
      description = "Resend API key allowed to send from media.humane.tools";
    };
    script = ''
      b64u() { basenc --base64url | tr -d '=\n'; }
      openssl rand -hex 32 | tr -d '\n' > "$out/telegram_webhook_secret"
      # VAPID as worker/scripts/generate-vapid.ts writes it: the raw P-256
      # point and the private scalar d, base64url. d sits at bytes 8..39 of
      # the SEC1 DER encoding.
      pem=$(mktemp)
      openssl ecparam -name prime256v1 -genkey -noout -out "$pem"
      openssl ec -in "$pem" -pubout -outform DER | tail -c 65 | b64u > "$out/vapid_public_key"
      vapid_private=$(openssl ec -in "$pem" -outform DER | head -c 39 | tail -c 32 | b64u)
      rm "$pem"
      {
        echo "INSTANT_APP_ADMIN_TOKEN=$(cat "$prompts/instant-admin-token")"
        echo "RESEND_API_KEY=$(cat "$prompts/resend-api-key")"
        echo "TELEGRAM_WEBHOOK_SECRET=$(cat "$out/telegram_webhook_secret")"
        echo "VAPID_PUBLIC_KEY=$(cat "$out/vapid_public_key")"
        echo "VAPID_PRIVATE_KEY=$vapid_private"
      } > "$out/env"
    '';
  };

  services.links-worker = {
    enable = true;
    # Releases ship with media-inbox's `just deploy-worker`, not a system
    # deploy; activation seeds the profile with the pinned package once.
    profile = "/nix/var/nix/profiles/links-worker";
    domains = [
      "worker.links.humane.tools"
      # Installed extensions bake these in; keep them as real API hosts.
      "worker.media.humane.tools"
      "worker.commonplace.humane.tools"
    ];
    environment = {
      INSTANT_APP_ID = "4d9d32c8-0766-4dad-9b3a-3068a405e693";
      ADMIN_EMAIL = "bah@posteo.de";
      APP_URL = "https://links.humane.tools";
      EMAIL_FROM = "recommendations@media.humane.tools";
      VAPID_SUBJECT = "mailto:bah@posteo.de";
    };
    environmentFiles = [ secrets.files."env".path ];
  };
}
