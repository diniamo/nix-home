packages: {lib, pkgs, config, ...}: let
  inherit (lib.options) mkOption literalExpression;
  inherit (lib.modules) mkIf;
  inherit (lib.types) path attrsOf submodule bool nullOr str lines;
  inherit (lib.attrsets) mapAttrsToList filterAttrs;
  inherit (lib.path.subpath) components;
  inherit (lib.lists) takeEnd optional;
  inherit (builtins) replaceStrings mapAttrs length elemAt concatStringsSep;

  inherit (pkgs) writeText writeScript;

  inherit (packages.${pkgs.system}) linker;

  cfg = config.home;

  pathToName = path: let
    directoryAndName = takeEnd 2 (components path);
  in concatStringsSep "-" directoryAndName;
  fileToEntry = link: file: let
    fullPath = "${cfg.directory}/${link}";
    onChangeScript =
      if file.onChange == ""
      then ""
      else writeScript "${file.source.name}-on-change" file.onChange;
  in "${fullPath}\t${file.source}\t${onChangeScript}";

  filesFiltered = filterAttrs (_: file: file.source != null) cfg.files;
  manifestEntries = mapAttrsToList fileToEntry filesFiltered;
  manifest = concatStringsSep "\n" manifestEntries;
  manifestFile = writeText "home-manifest" manifest;
in {
  options = {
    home = {
      user = mkOption {
        type = nullOr str;
        description = ''
          The user to link files for.
          If null, nix-home will be disabled.
          `users.users.<user>.createHome` must be true.
        '';
      };
      directory = mkOption {
        type = nullOr path;
        default = config.users.users.${cfg.user}.home;
        defaultText = literalExpression "config.users.users.\${config.home.user}";
        description = ''
          The directory to link files to.
          Normally, you should set {option}`home.user`, since that's what enables nix-home,
          and it's also used to check whether we are actually activating for the correct user
          in `system.userActivationScripts`.
        '';
      };

      files = mkOption {
        type = attrsOf (submodule ({name, config, ...}: {
          options = {
            source = mkOption {
              type = nullOr path;
              default = writeText (pathToName name) config.text;
              defaultText = literalExpression "writeText (pathToName \"<name>\") home.files.<name>.text";
              description = ''
                The source of the file.
                If {option}`home.file.<name>.text` is not null, this is set to a generated file filled with it.
              '';
            };

            text = mkOption {
              type = nullOr str;
              description = ''
                The text of the file.
                If this is not null, {option}`home.file.<name>.source` is set to a generated file filled with this.
              '';
            };

            onChange = mkOption {
              type = lines;
              default = "";
              description = "Shell commands to run when the file changes between generations.";
            };
          };
        }));
        default = {};
        description = ''
          Attribute set of files to link to the home directory.
          The attribute names are the link paths relative to the specified home directory.
        '';
      };
    };
  };

  config = mkIf (cfg.user != null) {
    warnings = let
      user = config.users.users.${cfg.user};
    in optional (!(cfg.directory == user.home -> user.createHome)) ''
      It looks like the target directory matches your home directory, but createHome is false.
      If the directory does not exist at activation, it will be created with 755 permissions,
      which is a security risk.
    '';

    system.userActivationScripts.home.text = ''
      if [[ "$USER" == "${cfg.user}" ]]; then
        echo "Linking home files"
        ${linker} ${cfg.directory}/.local/state/nix/profiles ${manifestFile}
      fi
    '';
  };
}
