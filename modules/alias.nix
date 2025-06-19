{lib, config, ...}: let
  inherit (lib.modules) mkAliasOptionModule;
in {
  imports = [
    (mkAliasOptionModule ["user"] ["users" "users" config.home.user])
  ];
}
