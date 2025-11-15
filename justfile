default:
  just --list

conventional-docker-build:
  docker build -t meilisearch-local-buildx .

nix-docker-build:
  nix build .#default -L --cores 2 # increase the job numbers if more ram is available
  docker load < result

run-conventional-docker-build:
  docker run -it --rm \
    -p 8080:8080 \
    -p 2022:2022 \
    ghcr.io/vncsmyrnk/sftpgo-traditional:latest

run-nix-docker-build:
  docker run -it --rm \
    -p 8080:8080 \
    -p 2022:2022 \
    ghcr.io/vncsmyrnk/sftpgo-nix:latest

application-connect-user:
  sftp -P 2022 user@localhost

application-open-web-admin:
  xdg-open http://localhost:8080/web/admin

application-open-web-client:
  xdg-open http://localhost:8080/web/client

generate-sboms:
  syft ghcr.io/vncsmyrnk/sftpgo-nix:latest -o spdx-json | jq > /tmp/sftpgo-nix-sbom.spdx.json
  syft ghcr.io/vncsmyrnk/sftpgo-traditional:latest -o spdx-json | jq > /tmp/sftpgo-traditional-sbom.spdx.json

scan-vulnerabilities: generate-sboms
  @echo 'Scanning the nix built image...'
  cat /tmp/sftpgo-nix-sbom.spdx.json | grype
  @echo 'Now scanning the traditional built one...'
  cat /tmp/sftpgo-traditional-sbom.spdx.json | grype

dependency-count:
  @echo 'Evaluating the nix SBOM...'
  jq '.packages[] | select((.sourceInfo // "") | contains("go module") | not) | .name' -r /tmp/vncsmyrnk-sftpgo-nix.spdx.json | sort --unique | wc -l
  @echo 'Evaluating the traditional built SBOM...'
  jq '.packages[] | select((.sourceInfo // "") | contains("go module") | not) | .name' -r /tmp/vncsmyrnk-sftpgo-traditional.spdx.json | sort --unique | wc -l
