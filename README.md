# FHIR-IRL-publication-tools

A general-purpose Docker image carrying the full HL7 FHIR IG publishing toolchain:
IG Publisher, FHIR Validator, SUSHI, GoFSH, Jekyll and Graphviz.

This repo is **not tied to any one Implementation Guide**. It is versioned and released
separately from the IGs that use it. An IG repo doesn't copy this code; it pulls the
published image and mounts its own project into it.

## Using the image

```
docker pull ghcr.io/hl7-ireland-shadow/fhir-irl-publication-tools:latest
```

From the root of any IG project (one with a `sushi-config.yaml` or `ig.ini`):

```
docker run --rm \
  -v "$PWD:/ig" \
  -v fhir-cache:/home/fhir/.fhir \
  -v ig-temp:/ig/temp \
  ghcr.io/hl7-ireland-shadow/fhir-irl-publication-tools:latest
```

Pin a version tag (e.g. `:1.2.0`) in IG repos that need reproducible builds.
See [docker/README.md](docker/README.md) for commands, configuration, volumes,
a docker-compose example and troubleshooting.

## Repository layout

| Path                                    | Purpose                                              |
|-----------------------------------------|------------------------------------------------------|
| `docker/Dockerfile`                     | The image definition                                 |
| `docker/fhir-tools`                     | Entrypoint script (`publish`, `sushi`, `validate`, …) |
| `docker/record-versions.sh`             | Records baked-in tool versions (`fhir-tools versions`) |
| `.github/workflows/docker-publish.yml`  | Builds and publishes the image to GHCR               |

## Releasing

- Pushes to `main` publish `:latest`.
- Pushing a `v*` tag (e.g. `v1.2.0`) publishes `:1.2.0` and `:1.2`.
- A weekly scheduled build refreshes `:latest` with the newest IG Publisher, Validator
  and SUSHI releases.

IG repos choose when to adopt a new image by changing the tag they reference.
