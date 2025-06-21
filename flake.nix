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
            enable = true;
            user = "alice";
            linkOnBoot = true;
            
            files.".config/test" = {
              name = "config-test";
              text = "test";
            };
          };
        };
        
        testScript = ''
          machine.start()
          machine.wait_for_unit('default.target')
          
          machine.succeed('test "$(cat /home/alice/.config/test)" = "test"')
        '';
      };
    });
  };
}
