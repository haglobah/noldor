{ self, ... }:
{
  imports = [ self.inputs.home-manager.nixosModules.default ];
  home-manager.users.beat = {
    imports = [
      ../../modules/home/home.nix
    ];
  };
}
