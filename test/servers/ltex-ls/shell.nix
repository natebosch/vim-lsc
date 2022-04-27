{ pkgs ? import <nixpkgs> {} }:
let ltex-ls = import ./ltex-ls.nix; in
pkgs.mkShell {
    nativeBuildInputs = [ ltex-ls ];
}
