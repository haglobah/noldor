{
  config = {
    programs.openclaw = {
      documents = ../dotfiles/openclaw;

      config = {
        gateway = {
          mode = "local";
        };
      };
    };
  };
}
