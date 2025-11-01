{
  description = "SFTPGo Docker image";

  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Build arguments from environment, similar to Dockerfile ARGs
      commitSha = builtins.getEnv "COMMIT_SHA";
      commitDate = builtins.getEnv "COMMIT_DATE";
      gitTag = builtins.getEnv "GIT_TAG";
      # For setting go build tags, e.g. "nos3,nogcs"
      features = builtins.getEnv "FEATURES";

      # Use git tag for version, fallback to commit sha
      version = if gitTag != "" then
        gitTag
      else if commitSha != "" then
        commitSha
      else
        "dirty";

      goSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let baseName = baseNameOf (toString path);
          in !((baseName == "flake.nix") || (baseName == "flake.lock")
            || (baseName == ".git") || (baseName == "result"));
      };

      sftpgo = pkgs.buildGoModule {
        pname = "sftpgo";
        inherit version;
        src = goSrc;

        # This hash is computed from the go.mod and go.sum files.
        # If you change dependencies, you'll need to update this.
        vendorHash = "sha256-LyqGOEhTQRSYlkjRYEhwFjK6iUWIxM1W7sY8nqEaUKA=";

        ldflags = [
          "-s"
          "-w"
          "-X github.com/drakkan/sftpgo/v2/internal/version.commit=${commitSha}"
          "-X github.com/drakkan/sftpgo/v2/internal/version.date=${commitDate}"
        ];

        # Corresponds to the FEATURES build-arg in the Dockerfile
        tags =
          if features != "" then pkgs.lib.splitString "," features else [ ];

        # Skip tests for faster builds
        doCheck = false;

        # The main package is in the root
        subPackages = [ "." ];
      };

      # Generate sftpgo.json with modifications from the Dockerfile
      sftpgo-json = pkgs.runCommand "sftpgo.json" { } ''
        cp ${goSrc}/sftpgo.json $out
        sed -i 's|"users_base_dir": "",|"users_base_dir": "/srv/sftpgo/data",|' $out
        sed -i 's|"backups"|"/srv/sftpgo/backups"|' $out
      '';

      dockerImage = pkgs.dockerTools.buildImage {
        name = "sftpgo-local-nix";
        tag = if version != "" then version else "latest";

        copyToRoot = pkgs.buildEnv {
          name = "image-root";
          paths = with pkgs; [ sftpgo cacert shadow ];
          pathsToLink = [ "/bin" "/sbin" "/usr/bin" ];
        };

        runAsRoot = ''
          #!${pkgs.runtimeShell}
          # Create directories from Dockerfile
          mkdir -p /etc/sftpgo /var/lib/sftpgo /usr/share/sftpgo /srv/sftpgo/data /srv/sftpgo/backups

          # Copy static assets and config
          cp -r ${goSrc}/templates /usr/share/sftpgo/templates
          cp -r ${goSrc}/static /usr/share/sftpgo/static
          cp -r ${goSrc}/openapi /usr/share/sftpgo/openapi
          cp ${sftpgo-json} /etc/sftpgo/sftpgo.json

          # Create user and group from Dockerfile
          groupadd --system -g 1000 sftpgo
          useradd --system --gid sftpgo --no-create-home \
            --home-dir /var/lib/sftpgo --shell /usr/sbin/nologin \
            --comment "SFTPGo user" --uid 1000 sftpgo

          # Set permissions from Dockerfile
          chown -R sftpgo:sftpgo /etc/sftpgo /srv/sftpgo
          chown sftpgo:sftpgo /var/lib/sftpgo
          chmod 700 /srv/sftpgo/backups
        '';

        config = {
          Env = [
            # Log to stdout, as in the Dockerfile
            "SFTPGO_LOG_FILE_PATH="
            "PATH=/bin:/sbin:/usr/bin"
          ];

          WorkingDir = "/var/lib/sftpgo";
          User = "1000:1000";

          Cmd = [ "${sftpgo}/bin/sftpgo" "serve" ];

          Labels = {
            "org.opencontainers.image.source" =
              "https://github.com/drakkan/sftpgo";
          };
        };
      };
    in {
      packages.${system} = {
        default = dockerImage;
        sftpgo = sftpgo;
        docker = dockerImage;
      };
    };
}
