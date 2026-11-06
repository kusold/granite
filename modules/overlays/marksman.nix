# Overlay: marksman from upstream prebuilt release binaries
#
# nixpkgs' marksman is a .NET source build that misses cache.nixos.org for
# darwin (release-branch pins get no Hydra darwin builds), so every rebuild
# compiles the whole dotnet toolchain from source — 30+ minutes. Upstream
# publishes release binaries instead: a universal macOS binary (x86_64 +
# aarch64) and glibc Linux builds, patched with autoPatchelfHook so they run
# on NixOS (the reason marksman comes from home-manager at all, #21 — Mason's
# binary is glibc-linked and exits 127 there).
{ ... }:
{
  flake.overlays.marksman =
    final: prev:
    let
      version = "2026-02-08";

      # Upstream asset for this platform; null (e.g. i686-linux) falls back
      # to the nixpkgs source build.
      asset =
        if final.stdenv.hostPlatform.isDarwin then
          "marksman-macos"
        else if final.stdenv.hostPlatform.isx86_64 then
          "marksman-linux-x64"
        else if final.stdenv.hostPlatform.isAarch64 then
          "marksman-linux-arm64"
        else
          null;
    in
    {
      marksman =
        if asset == null then
          prev.marksman
        else
          final.stdenv.mkDerivation {
            pname = "marksman";
            inherit version;
            src = final.fetchurl {
              url = "https://github.com/artempyanykh/marksman/releases/download/${version}/${asset}";
              hash =
                {
                  marksman-macos = "sha256-aoAcF7WsDbppeHxSgrOzvUFuZsliU/rgmNMRxrvRgzs=";
                  marksman-linux-x64 = "sha256-vlCY6CEyGSacR/wNkWpm+jHOBgLslnR1xyImCqvyYIc=";
                  marksman-linux-arm64 = "sha256-244SRSf3+ASOPmyRghucUu8XPZLAHkfSIb8TN6/ZYvs=";
                }
                .${asset};
            };
            dontUnpack = true;
            dontConfigure = true;
            dontBuild = true;
            # The appended .NET single-file bundle is not debug info; strip
            # truncates it and the binary dies with "Bounds check failed
            # while reading the bundle".
            dontStrip = true;
            # The Linux binaries are glibc-linked: repoint the interpreter at
            # nix glibc and resolve libstdc++/libgcc_s. The macOS binary is
            # self-contained and needs nothing.
            nativeBuildInputs = final.lib.optionals final.stdenv.hostPlatform.isLinux [
              final.autoPatchelfHook
            ];
            buildInputs = final.lib.optionals final.stdenv.hostPlatform.isLinux [
              final.stdenv.cc.cc.lib
            ];
            installPhase = ''
              runHook preInstall
              install -Dm555 $src $out/bin/marksman
              runHook postInstall
            '';
            meta = (prev.marksman.meta or { }) // {
              sourceProvenance = [ final.lib.sourceTypes.binaryNativeCode ];
            };
          };
    };
}
