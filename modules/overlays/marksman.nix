# Overlay: marksman from upstream prebuilt release binaries
#
# nixpkgs' marksman is a .NET source build that misses cache.nixos.org for
# darwin (release-branch pins get no Hydra darwin builds), so every rebuild
# compiled the whole dotnet toolchain from source — 30+ minutes. Upstream
# publishes release binaries instead: a universal macOS binary (x86_64 +
# aarch64) and glibc Linux builds, patched with autoPatchelfHook so they run
# on NixOS (the reason marksman comes from home-manager at all, #21 — Mason's
# binary is glibc-linked and exits 127 there).
#
# Renovate keeps the release tag in each url and the hash next to it current
# (customManagers in renovate.json5). The hashes must stay `sha256:` + plain
# hex: Renovate's github-release-attachments datasource identifies the asset
# by its digest, and only a 64-char hex digest is recognized as sha256 — the
# SRI/base32 nix forms would be misread and updates would land with stale
# hashes.
{ ... }:
{
  flake.overlays.marksman =
    final: prev:
    let
      # One entry per upstream asset; the tag inside the url is the single
      # source of truth for the version.
      assets = {
        marksman-macos = {
          url = "https://github.com/artempyanykh/marksman/releases/download/2026-02-08/marksman-macos";
          hash = "sha256:6a801c17b5ac0dba69787c5282b3b3bd416e66c96253fae098d311c6bbd1833b";
        };
        marksman-linux-x64 = {
          url = "https://github.com/artempyanykh/marksman/releases/download/2026-02-08/marksman-linux-x64";
          hash = "sha256:be5098e8213219269c47fc0d916a66fa31ce0602ec967475c722260aabf26087";
        };
        marksman-linux-arm64 = {
          url = "https://github.com/artempyanykh/marksman/releases/download/2026-02-08/marksman-linux-arm64";
          hash = "sha256:db8e124527f7f8048e3e6c91821b9c52ef173d92c01e47d221bf1337afd962fb";
        };
      };

      # No upstream asset (e.g. i686-linux) means null, which falls back to
      # the nixpkgs source build.
      asset =
        if final.stdenv.hostPlatform.isDarwin then
          "marksman-macos"
        else if final.stdenv.hostPlatform.isx86_64 then
          "marksman-linux-x64"
        else if final.stdenv.hostPlatform.isAarch64 then
          "marksman-linux-arm64"
        else
          null;

      assetSrc = if asset == null then null else assets.${asset};

      version = builtins.head (builtins.match ".*/download/([^/]+)/[^/]+$" assetSrc.url);
    in
    {
      marksman =
        if assetSrc == null then
          prev.marksman
        else
          final.stdenv.mkDerivation {
            pname = "marksman";
            inherit version;
            src = final.fetchurl {
              inherit (assetSrc) url hash;
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
