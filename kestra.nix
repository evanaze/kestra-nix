# Compatibility shim: re-export the NixOS module from its canonical location.
# Primary import path is modules/services/kestra/default.nix.
{ lib, ... }: lib.warnOnce
  "kestra.nix root shim is deprecated; import modules/services/kestra/default.nix directly"
  (import ./modules/services/kestra/default.nix)
