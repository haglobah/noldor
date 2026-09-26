# The hostname other machines ship metrics and logs to (./metrics.nix on
# formenos serves it, ./metrics-shipper.nix sends to it). DNS points it
# at formenos.
{
  ingestHost = "metrics.humane.tools";
}
