# The flow-backup command (./flow-backup.sh), a package: ./flow.nix runs it
# every 20 minutes, tests/flow-backup.nix tests it (with a fake curl).
#
# It pushes the hotlustre checkout Flow's core runs from and Flow's version
# graph (repo.git) to GitHub. It used to be two plain `git push`es: on
# 2026-11-19 someone pushed hotlustre's main from the laptop, the checkout's
# main was behind, GitHub rejected it as non-fast-forward, and the unit failed
# for hours with nothing else pushed. Now it must never block:
# - one `git push --porcelain` per repository, never forced, read ref by ref;
# - a rejected ref whose commits GitHub already has (pushed on top from
#   elsewhere) is fine; it is fast-forwarded here unless a worktree has it
#   checked out (the core's files move only by a deploy, flow-update-hotlustre);
# - a diverged ref goes to refs/backup/<host>/<ref without refs/> on GitHub
#   (forced, ours), so nothing is lost, and the owner hears of it by ntfy once
#   per change of the set of diverged refs, and once when it is empty again.
#   GitHub takes custom ref namespaces (refs/versions/* has been pushed there
#   all along), and refs outside refs/heads/ show as no branch and start no
#   push workflow.
# Only a failed push or fetch (network, auth) fails the unit, after the
# other repository is done; Flow's health check lists failed units.
{
  writeShellApplication,
  git,
  openssh,
  curl,
  coreutils,
  gnugrep,
  gnused,
}:
writeShellApplication {
  name = "flow-backup";
  runtimeInputs = [
    git
    openssh
    curl
    coreutils
    gnugrep
    gnused
  ];
  text = builtins.readFile ./flow-backup.sh;
}
