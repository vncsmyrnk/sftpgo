default:
  just --list

conventional-docker-build:
  docker build -t meilisearch-local-buildx .

nix-docker-build:
  nix build .#default -L --cores 2 # increase the job numbers if more ram is available
  docker load < result
