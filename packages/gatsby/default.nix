{ pkgs ? import <nixpkgs> {} }:
let
  src = pkgs.fetchFromGitHub {
    owner = "redbrick";
    repo = "react-site";
    rev = "24c2c767cd48b61a3f66ae97b53d68d4d1b698ca";
    sha256 = "0rxbavdkarskgrr6v4g5c1xbvm1ddgvplnflnhnir0j7xy0ajhv8";
  };
  npmlock2nix = import (./npmlock2nix) { inherit pkgs; };
in npmlock2nix.build {
  inherit src;
  installPhase = "cp -r dist $out";
  node_modules_attrs = {
    buildInputs = with pkgs; [ vips python3 ];
    nativeBuildInputs = with pkgs; [ pkgconfig gobject-introspection ];
    preInstallLinks.pngquant-bin."vendor/pngquant" = "${pkgs.pngquant}/bin/pngquant";
  };
}
