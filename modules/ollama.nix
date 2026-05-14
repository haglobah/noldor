{
  config = {
    services.ollama = {
      enable = true;
      loadModels = [ "gemma4:4b" ];
    };
  };
}
