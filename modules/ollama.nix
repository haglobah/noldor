{ pkgs, ... }:
{
  config = {
    services.ollama = {
      enable = true;
      package = pkgs.ollama-rocm;
      rocmOverrideGfx = "11.0.0";
      loadModels = [ "gemma4:e4b" ];
    };
  };
}
