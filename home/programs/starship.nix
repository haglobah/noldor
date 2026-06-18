{ config, ... }:
let
  compactToolchains = [
    "bun"
    "c"
    "cmake"
    "cobol"
    "crystal"
    "daml"
    "dart"
    "deno"
    "dotnet"
    "elixir"
    "elm"
    "erlang"
    "fennel"
    "golang"
    "gradle"
    "haskell"
    "haxe"
    "helm"
    "java"
    "julia"
    "kotlin"
    "lua"
    "nim"
    "nodejs"
    "ocaml"
    "opa"
    "perl"
    "php"
    "pulumi"
    "purescript"
    "python"
    "quarto"
    "raku"
    "red"
    "rlang"
    "ruby"
    "rust"
    "scala"
    "solidity"
    "swift"
    "terraform"
    "typst"
    "vagrant"
    "vlang"
    "zig"
  ];
  compact = {
    format = "[$symbol$version ]($style)";
  };
in
{
  programs.starship = {
    enable = true;

    enableBashIntegration = true;
    enableFishIntegration = true;

    # Configuration written to ~/.config/starship.toml
    settings = {
      add_newline = false;

      format = builtins.concatStringsSep "" [
        "$line_break"
        "$all"
      ];

      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };

      battery = {
        display = [
          {
            threshold = 30;
            style = "bold red";
          }
        ];
      };

      nix_shell = {
        format = "[$symbol$state ]($style)";
      };
    }
    // builtins.listToAttrs (
      map (n: {
        name = n;
        value = compact;
      }) compactToolchains
    );
  };
}
