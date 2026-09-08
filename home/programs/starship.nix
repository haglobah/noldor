{ config, ... }:
let
  compactToolchains = [
    "buf"
    "bun"
    "c"
    "cmake"
    "cobol"
    "cpp"
    "crystal"
    "daml"
    "dart"
    "deno"
    "dotnet"
    "elm"
    "erlang"
    "fennel"
    "fortran"
    "gleam"
    "golang"
    "gradle"
    "haskell"
    "haxe"
    "helm"
    "java"
    "julia"
    "kotlin"
    "lua"
    "maven"
    "mojo"
    "nim"
    "nodejs"
    "ocaml"
    "odin"
    "opa"
    "perl"
    "php"
    "purescript"
    "quarto"
    "raku"
    "red"
    "rlang"
    "ruby"
    "rust"
    "scala"
    "solidity"
    "swift"
    "typst"
    "vagrant"
    "vlang"
    "xmake"
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

      gcloud = {
        format = "[$symbol$account ]($style)";
      };

      # Starship defaults with the "via"/"on"/"is" prefix word removed.
      # These keep fields the shared compact format would drop.
      aws.format = "[$symbol($profile )(\\($region\\) )(\\[$duration\\] )]($style)";
      azure.format = "[$symbol($subscription) ]($style)";
      openstack.format = "[$symbol$cloud(\\($project\\)) ]($style)";

      git_branch.format = "[$symbol$branch(:$remote_branch) ]($style)";
      hg_branch.format = "[$symbol$branch(:$topic) ]($style)";
      fossil_branch.format = "[$symbol$branch ]($style)";
      pijul_channel.format = "[$symbol$channel ]($style)";

      package.format = "[$symbol$version ]($style)";
      docker_context.format = "[$symbol$context ]($style)";
      meson.format = "[$symbol$project ]($style)";

      conda.format = "[$symbol$environment ]($style)";
      spack.format = "[$symbol$environment ]($style)";
      guix_shell.format = "[$symbol]($style) ";
      pixi.format = "[$symbol($version )(\\($environment\\) )]($style)";

      elixir.format = "[$symbol($version \\(OTP $otp_version\\) )]($style)";
      python.format = "[$symbol$pyenv_prefix($version )(\\($virtualenv\\) )]($style)";
      pulumi.format = "[$symbol($username@)$stack ]($style)";
      terraform.format = "[$symbol$workspace ]($style)";
    }
    // builtins.listToAttrs (
      map (n: {
        name = n;
        value = compact;
      }) compactToolchains
    );
  };
}
