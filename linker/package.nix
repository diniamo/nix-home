{stdenvNoCC, lib, odin}: stdenvNoCC.mkDerivation {
  name = "nix-home-linker";

  src = ./main.odin;
  dontUnpack = true;

  buildInputs = [ odin ];

  buildPhase = ''
    runHook preBuild
    
    odin build $src -file -o:speed -out:$out
    
    runHook postBuild
  '';
  dontInstall = true;

  meta = {
    description = "Linker for nix-home";
    homepage = "https://github.com/diniamo/nix-home/tree/main/linker";
    license = lib.licenses.eupl12;
    platforms = lib.platforms.linux;
    maintainers = [lib.maintainers.diniamo];
  };
}
