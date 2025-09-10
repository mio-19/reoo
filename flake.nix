{
  description = "Wireguird (WireGuard GUI) packaged as a flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # supported systems (add/remove as you need)
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      wireguirdOverlay = final: prev: {
        wireguird = final.buildGoModule rec {
          pname = "wireguird";
          version = "unstable-2025-09-04";

          go = final.go;

          # Parallel builds (Nix + Go)
          enableParallelBuilding = true;
          buildFlagsArray = [
            "-p"
            "$NIX_BUILD_CORES"
          ];

          src = final.fetchFromGitHub {
            owner = "UnnoTed";
            repo = "wireguird";
            rev = "master"; # consider pinning a commit for reproducibility
            sha256 = "sha256-iv0/HSu/6IOVmRZcyCazLdJyyBsu5PyTajLubk0speI=";
          };

          # Build from repo root
          modRoot = ".";
          subPackages = [ "." ];

          vendorHash = "sha256-/MeaomhmQL3YNrR4a0ihGwZAo5Zk8snpJvCSXY93aM8=";

          # GUI needs CGO; parallelize runtime/test; mute GLib deprecation warnings
          env = {
            CGO_ENABLED = "1";
            GOMAXPROCS = "$NIX_BUILD_CORES";
            CGO_CFLAGS = "-Wno-deprecated-declarations";
            CGO_CXXFLAGS = "-Wno-deprecated-declarations";
          };

          nativeBuildInputs = [
            final.pkg-config
            final.makeWrapper
          ];

          buildInputs = [
            final.gtk3
            final.libayatana-appindicator
            final.gdk-pixbuf
            final.glib
            final.xorg.libX11
            final.xorg.libXcursor
            final.xorg.libXrandr
            final.xorg.libXinerama
            final.xorg.libXi
          ];

          # Only patch the icon path; don't touch go.mod.
          postPatch = ''
            substituteInPlace gui/gui.go \
              --replace-fail 'IconPath    = "/opt/wireguird/Icon/"' \
                             'IconPath    = "/run/current-system/sw/share/wireguird/Icon/"'
            # Remove any existing vendor directory to avoid inconsistency
            rm -rf vendor || true
          '';

          ldflags = [
            "-s"
            "-w"
          ];

          postInstall = ''
            # Icons (program path)
            install -Dm644 -t "$out/share/wireguird/Icon/16x16"   Icon/16x16/wireguard.png   || true
            install -Dm644 -t "$out/share/wireguird/Icon/32x32"   Icon/32x32/wireguard.png   || true
            install -Dm644 -t "$out/share/wireguird/Icon/48x48"   Icon/48x48/wireguard.png   || true
            install -Dm644 -t "$out/share/wireguird/Icon/128x128" Icon/128x128/wireguard.png || true
            install -Dm644 -t "$out/share/wireguird/Icon/256x256" Icon/256x256/wireguard.png || true
            if [ -f Icon/wireguard.svg ]; then
              install -Dm644 Icon/wireguard.svg "$out/share/wireguird/Icon/wireguard.svg"
            fi

            # hicolor theme (so Icon=wireguird works from the desktop file)
            for sz in 16x16 32x32 48x48 128x128 256x256; do
              if [ -f "Icon/$sz/wireguard.png" ]; then
                install -Dm644 "Icon/$sz/wireguard.png" \
                  "$out/share/icons/hicolor/$sz/apps/wireguird.png"
              fi
            done
            if [ -f Icon/wireguard.svg ]; then
              install -Dm644 Icon/wireguard.svg \
                "$out/share/icons/hicolor/scalable/apps/wireguird.svg"
            fi

            # Desktop entry
            install -Dm644 /dev/stdin "$out/share/applications/wireguird.desktop" <<EOF
              [Desktop Entry]
              Type=Application
              Name=Wireguird
              Comment=WireGuard GUI
              Exec=pkexec $out/bin/wireguird
              Terminal=false
              Icon=wireguird
              Categories=Network;Security;
            EOF

            # Polkit policy (pkexec target must match)
            install -Dm644 /dev/stdin "$out/share/polkit-1/actions/wireguird.policy" <<EOF
              <?xml version="1.0" encoding="UTF-8"?>
              <!DOCTYPE policyconfig PUBLIC
               "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
               "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
              <policyconfig>
                <action id="org.freedesktop.policykit.pkexec.wireguird">
                  <description>Wireguard GUI</description>
                  <message>Authentication is required to run wireguird</message>
                  <defaults>
                    <allow_any>auth_admin</allow_any>
                    <allow_inactive>auth_admin</allow_inactive>
                    <allow_active>auth_admin</allow_active>
                  </defaults>
                  <annotate key="org.freedesktop.policykit.exec.path">$out/bin/wireguird</annotate>
                  <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
                </action>
              </policyconfig>
            EOF

            # Ensure wg/wg-quick & resolvconf are available at runtime.
            wrapProgram "$out/bin/wireguird" \
              --prefix PATH : ${
                final.lib.makeBinPath [
                  final.wireguard-tools
                  final.openresolv
                ]
              }
          '';

          meta = with final.lib; {
            description = "Wireguard GUI (Nix package with desktop entry + polkit)";
            homepage = "https://github.com/UnnoTed/wireguird";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "wireguird";
          };
        };
      };
    in
    {
      overlays.default = wireguirdOverlay;

      packages = forAllSystems (
        pkgs:
        let
          pkgs' = import nixpkgs {
            inherit (pkgs) system;
            overlays = [ wireguirdOverlay ];
          };
        in
        {
          wireguird = pkgs'.wireguird;
          default = pkgs'.wireguird;
        }
      );

      apps = forAllSystems (pkgs: {
        wireguird = {
          type = "app";
          program = "${self.packages.${pkgs.system}.wireguird}/bin/wireguird";
        };
        default = self.apps.${pkgs.system}.wireguird;
      });
    };
}
