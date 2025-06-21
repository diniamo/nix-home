packages: { lib, pkgs, config, ... }: let
  inherit (lib.options) mkEnableOption mkOption literalExpression;
  inherit (lib.modules) mkIf;
  inherit (lib.types) path attrsOf submodule bool nullOr str lines package either;
  inherit (lib.attrsets) mapAttrsToList filterAttrs;
  inherit (lib.lists) optional;
  inherit (lib.strings) optionalString;
  inherit (builtins) replaceStrings mapAttrs length elemAt concatStringsSep baseNameOf;

  inherit (pkgs) writeText writeScript;

  inherit (packages.${pkgs.system}) linker;

  cfg = config.home;
  user = config.users.users.${cfg.user};

  fileToEntry = relative: file: let
    link = "${cfg.directory}/${relative}";
    target = optionalString (file.source != null) file.source;
    onChangeScript = optionalString (file.onChange != null) (writeScript "${file.name}-on-change.sh" file.onChange);
  in "${link}\t${target}\t${onChangeScript}";

  manifestEntries = mapAttrsToList fileToEntry cfg.files;
  manifest = concatStringsSep "\n" manifestEntries;
  manifestFile = writeText "home-manifest" manifest;
in {
  options = {
    home = {
      enable = mkEnableOption "nix-home";
      user = mkOption {
        type = str;
        description = ''
          The user to link files for.
          If null, nix-home will be disabled.
          `users.users.<user>.createHome` must be true.
        '';
      };
      directory = mkOption {
        type = path;
        default = config.users.users.${cfg.user}.home;
        defaultText = literalExpression "config.users.users.\${config.home.user}";
        description = ''
          The directory to link files to.
          Normally, you should set {option}`home.user`, since that's what enables nix-home,
          and it's also used to check whether we are actually activating for the correct user
          in `system.userActivationScripts`.
        '';
      };
      linkOnBoot = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to run the linker on boot.
          This is only useful, if you set the boot entry without switching to the configuration, or if you do impermenance.
        '';
      };

      files = mkOption {
        type = attrsOf (submodule ({ config, name, ... }: {
          options = {
            name = mkOption {
              type = str;
              default =
                if config.source != null && config.source ? name then config.source.name
                else baseNameOf name;
              description = ''
                The name of the generated store path.
                Defaults to the name attribute of {option}`home.files.<name>.source` or the base of the attribute name.
                This is only used when {option}`home.files.<name>.text` is set,
                or when {option}`home.files.<name>.source` is a path (and therefore doesn't have a `name` attribute).
              '';
            };
            
            source = mkOption {
              type = nullOr (either package path);
              default =
                if config.text != null then writeText config.name config.text
                else null;
              description = ''
                The source of the file.
                If this is a path, {option}`home.files.<name>.name` must be set as well.
                If {option}`home.files.<name>.text` is set, this will be set to a generated file filled with that option.
                If null (the default), the linker will only perform garbage collection on the file.
              '';
            };

            text = mkOption {
              type = nullOr str;
              default = null;
              description = ''
                The text of the file.
                If set, {option}`home.files.<name>.name` must be set as well.
                If set, {option}`home.files.<name>.source` is set to a generated file filled with this.
              '';
            };

            onChange = mkOption {
              type = nullOr lines;
              default = null;
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

  config = mkIf (cfg.enable && user.enable) {
    warnings = optional (!user.createHome && cfg.directory == user.home) ''
      It looks like the target directory matches your home directory, but createHome is false.
      If the directory does not exist at activation, it will be created with 755 permissions,
      which is a security risk.
    '';

    systemd.services.nix-home = {
      description = "home file linking";

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        ExecStart = "${linker} ${cfg.directory}/.local/state/nix/profiles ${manifestFile}";
      };

      requiredBy = [ "sysinit-reactivation.target" ]
        ++ optional cfg.linkOnBoot "default.target";
    };
  };
}
