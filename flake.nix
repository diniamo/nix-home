{
  description = "Bare-bones, single-user home file linker for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs = {nixpkgs, systems, self, ...}: let
    eachSystem = callback: nixpkgs.lib.genAttrs (import systems) (system: callback nixpkgs.legacyPackages.${system});
  in {
    devShells = eachSystem (pkgs: {
      default = with pkgs; mkShellNoCC {
        packages = [
          odin
          ols
        ];
      };
    });

    packages = eachSystem (pkgs: {
      linker = pkgs.callPackage ./linker/package.nix {};
    });
    
    nixosModules = let
      base = import ./modules/base.nix self.packages;
    in {
      default = base;
      base = base;
      alias = ./modules/alias.nix;
    };

    checks = eachSystem (pkgs: {
      default = pkgs.testers.runNixOSTest {
        name = "nix-home";
        
        nodes.machine = {pkgs, ...}: {
          imports = [ self.nixosModules.default ];

          users.users.alice.isNormalUser = true;
          services.getty.autologinUser = "alice";

          home = {
            user = "alice";
            files.".config/test".text = "test";
          };
        };
        
        testScript = ''
          machine.start()

          machine.wait_until_tty_matches('1', 'alice@machine')

          machine.wait_for_file('/home/alice/.config/test')
          machine.succeed('test "$(cat /home/alice/.config/test)" = "test"')
        '';
      };
    });
  };
}
