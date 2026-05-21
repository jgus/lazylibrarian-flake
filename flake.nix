{
  description = "LazyLibrarian: eBook/audiobook/magazine manager (LazyLibrarian/LazyLibrarian).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    slskd-api = {
      url = "github:jgus/slskd-api-flake/v0.2.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    iso639-lang = {
      # iso639-lang: similar-name nixpkgs siblings (`python-iso639`, `iso-639`) aren't substitutes — upstream imports the `Lang` class from `iso639-lang`.
      url = "github:jgus/iso639-lang-flake/v2.6.3";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, slskd-api, iso639-lang }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pin = import ./pin.nix;
        inherit (pin) version sourceRev sourceHash;
        pkgs = import nixpkgs { inherit system; };
        slskd-api-pkg = slskd-api.packages.${system}.slskd-api;
        iso639-lang-pkg = iso639-lang.packages.${system}.iso639-lang;
        python = pkgs.python3.withPackages (ps: with ps; [
          beautifulsoup4
          html5lib
          webencodings
          requests
          pysocks
          urllib3
          pyopenssl
          cherrypy
          cherrypy-cors
          httpagentparser
          mako
          httplib2
          pillow
          apprise
          pypdf
          python-magic
          rapidfuzz
          deluge-client
          pyparsing
          irc
          apscheduler
          tzdata
          slskd-api-pkg
          lxml
          iso639-lang-pkg
          xmltodict
        ]);
        lazylibrarian = pkgs.stdenv.mkDerivation {
          pname = "lazylibrarian";
          inherit version;
          src = pkgs.fetchFromGitLab {
            owner = "LazyLibrarian";
            repo = "LazyLibrarian";
            rev = sourceRev;
            hash = sourceHash;
          };
          nativeBuildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/lazylibrarian $out/bin
            cp -r . $out/lib/lazylibrarian/
            makeWrapper ${python}/bin/python3 $out/bin/lazylibrarian \
              --add-flags "$out/lib/lazylibrarian/LazyLibrarian.py"
            runHook postInstall
          '';
          meta.mainProgram = "lazylibrarian";
        };
        update-version = pkgs.writeShellApplication {
          name = "update-version";
          text = ''exec ${./update-version.sh} "$@"'';
        };
      in
      {
        packages = {
          inherit lazylibrarian update-version;
          default = lazylibrarian;
        };
      });
}
