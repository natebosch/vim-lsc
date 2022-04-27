with import <nixpkgs> {};
stdenv.mkDerivation {
  name = "ltex-ls";
  src = fetchurl {
    url = "https://github.com/valentjn/ltex-ls/releases/download/15.2.0/ltex-ls-15.2.0-linux-x64.tar.gz";
    sha256 = "1z1712pfzmmyb7jnhqkvix8mknhs30wlwmc397w93zzhdsxf5mq4";
  };
  installPhase = "mkdir $out; cp -r * $out";
}
