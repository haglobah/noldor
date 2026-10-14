# The nix-builds scheduler (../README.md). Stdlib only; openssl signs the
# GitHub App's JWT. nix is the machine's own, put on PATH by the module.
{
  lib,
  python3Packages,
  openssl,
}:
python3Packages.buildPythonApplication {
  pname = "nix-builds";
  version = "0.1.0";
  pyproject = true;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./nix_builds
      ./tests
    ];
  };
  build-system = [ python3Packages.setuptools ];

  makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ openssl ]}" ];

  nativeCheckInputs = [ openssl ];
  checkPhase = ''
    runHook preCheck
    python -m unittest discover -s tests -t . -v
    runHook postCheck
  '';

  meta.mainProgram = "nix-builds";
}
