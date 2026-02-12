{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation rec {
  pname = "hapi";
  version = "0.15.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@twsxtd/hapi/-/hapi-${version}.tgz";
    sha256 = "09jikq4kjx5zsr89gs455pcg3pyffakq8nbh5jhx6nw7fn3ac6rd";
  };

  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out/bin

    # Install the hapi binary
    cp -r package/bin/hapi.cjs $out/bin/hapi

    runHook postInstall
  '';

  meta = {
    description = "App for Claude Code / Codex / Gemini / OpenCode, vibe coding anytime, anywhere";
    homepage = "https://github.com/tiann/hapi";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hapi";
  };
}
