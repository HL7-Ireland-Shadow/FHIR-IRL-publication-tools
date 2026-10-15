# FHIR IG publishing image

A general-purpose image carrying the whole HL7 publishing toolchain, so the only thing
you need installed is Docker. It is not specific to any IG: it is built and released
from this repo, separately from the IGs that use it, and published to
`ghcr.io/hl7-ireland-shadow/fhir-irl-publication-tools`. Every run of a given tag uses
identical tool versions.

## Quick start

From the root of an IG project, pull the image and run it:

```
docker pull ghcr.io/hl7-ireland-shadow/fhir-irl-publication-tools:latest
docker run --rm -v "$PWD:/ig" -v fhir-cache:/home/fhir/.fhir -v ig-temp:/ig/temp \
  ghcr.io/hl7-ireland-shadow/fhir-irl-publication-tools:latest     # SUSHI + IG Publisher -> ./output
```

Open `output/index.html` for the rendered guide and `output/qa.html` for the QA report.

IG repos should pin a version tag instead of `latest`, and typically wrap the command
in their own `docker-compose.yml` (see [Using it from an IG repo](#using-it-from-an-ig-repo)).
To build the image locally while working on the tools themselves:
`docker build -t fhir-publishing-tools:local docker`.

The first run takes roughly 20 minutes; it downloads the FHIR packages and the IG
template, and populates the terminology cache. Later runs reuse all three and finish in
about 5 minutes.

## What's in the image

| Tool                                 | Role                                                  |
|--------------------------------------|-------------------------------------------------------|
| IG Publisher (`publisher.jar`)       | renders the IG                                        |
| FHIR Validator (`validator_cli.jar`) | validates resources standalone                        |
| SUSHI                                | compiles `input/fsh/*.fsh` to FHIR resources          |
| GoFSH                                | the reverse\: existing FHIR resources back to FSH     |
| Ruby + Jekyll                        | the Publisher shells out to Jekyll for page rendering |
| Graphviz                             | `dot`, for the Publisher's PlantUML diagrams          |
| JDK 21, Node 22, git, jq, python3    | runtimes the above expect                             |

Exact versions in your build:

```
docker compose run --rm publish versions
```

## Services

These assume the IG repo has a `docker-compose.yml` like the one under
[Using it from an IG repo](#using-it-from-an-ig-repo). The compose file lives in the IG
repo, not here.

| Command                           | What it does                                                                    |
|-----------------------------------|---------------------------------------------------------------------------------|
| `docker compose run --rm publish` | `sushi build .` then the IG Publisher. The normal build.                        |
| `docker compose run --rm sushi`   | FSH compile only\: seconds, not minutes. The inner loop while writing profiles. |
| `docker compose run --rm shell`   | Interactive bash with every tool on `PATH`.                                     |
| `docker compose run --rm clean`   | Deletes `output/`, `temp/`, `input-cache/`, `fsh-generated/`, `template/`.      |

Anything after the service name replaces the default command, so the same image doubles
as a toolbox:

```
docker compose run --rm shell validate fsh-generated/resources/Patient-ie.json
docker compose run --rm shell gofsh ./some-resource.json -o ./out
docker compose run --rm shell publisher -help
docker compose run --rm publish publish -no-narrative      # extra args go to the Publisher
```

## Where things end up

| Path                                     | Lives on                       | Why                                                                          |
|------------------------------------------|--------------------------------|------------------------------------------------------------------------------|
| `output/`, `fsh-generated/`, `template/` | your disk (bind mount)         | you need to read them                                                        |
| `temp/`                                  | Docker volume `ig-temp`        | the Publisher writes SQLite here, and a Windows/macOS bind mount corrupts it |
| `input-cache/`                           | Docker volume `ig-input-cache` | terminology cache; survives runs                                             |
| `~/.fhir`                                | Docker volume `fhir-cache`     | FHIR packages + IG templates; survives runs                                  |

All of the on-disk ones are gitignored.

To wipe the caches and start completely fresh:

```
docker compose down -v
```

## Configuration

Set these on the command line or in a `.env` file beside `docker-compose.yml`.

| Variable                                                     | Default                           | Purpose                                                                                                                |
|--------------------------------------------------------------|-----------------------------------|------------------------------------------------------------------------------------------------------------------------|
| `TX_SERVER`                                                  | Publisher default (`tx.fhir.org`) | Terminology server, passed as `-tx`. Use `n/a` to skip terminology validation: much faster, but bindings go unchecked. |
| `JAVA_OPTS`                                                  | `-Xmx4g -Dfile.encoding=UTF-8`    | JVM flags. Raise the heap for large IGs.                                                                               |
| `SKIP_SUSHI`                                                 | unset                             | `1` makes `publish` skip the SUSHI step.                                                                               |
| `IG_DIR`                                                     | `/ig`                             | IG root inside the container.                                                                                          |
| `IG_PUBLISHER_VERSION`/`_SHA256`, `VALIDATOR_VERSION`/`_SHA256`, `SUSHI_VERSION`, `GOFSH_VERSION`, `BUNDLER_VERSION` | pinned in `Dockerfile` | **Build** args for this repo's image. A JAR version must be changed together with its sha256 or the build fails. IG repos get this by pinning an image tag. |

```
TX_SERVER=n/a docker compose run --rm publish          # fast build, no terminology server
JAVA_OPTS=-Xmx8g docker compose run --rm publish       # more heap
```

## Using it from an IG repo

The image isn't tied to any IG: mount any IG project at `/ig`.

```powershell
docker run --rm `
  -v "${PWD}:/ig" `
  -v fhir-cache:/home/fhir/.fhir `
  -v ig-temp:/ig/temp `
  ghcr.io/hl7-ireland-shadow/fhir-irl-publication-tools:latest
```

(Bash: same thing with `\` continuations and `"$PWD:/ig"`.)

An IG repo would normally keep a `docker-compose.yml` that references a pinned tag and
mounts the caches, for example:

```yaml
services:
  publish: &base
    image: ghcr.io/hl7-ireland-shadow/fhir-irl-publication-tools:1.0.0
    volumes:
      - .:/ig
      - fhir-cache:/home/fhir/.fhir
      - ig-temp:/ig/temp
      - ig-input-cache:/ig/input-cache
    environment:
      TX_SERVER: ${TX_SERVER:-}
      JAVA_OPTS: ${JAVA_OPTS:--Xmx4g -Dfile.encoding=UTF-8}
  sushi:
    <<: *base
    command: sushi build .
  shell:
    <<: *base
    command: shell
  clean:
    <<: *base
    command: clean
volumes:
  fhir-cache:
  ig-temp:
  ig-input-cache:
```

Upgrading the toolchain is then a one-line tag change in the IG repo.

## Troubleshooting

**`SQLITE_CORRUPT ... DBBuilder`**: the Publisher's SQLite database ended up on a
Windows/macOS bind mount. The compose file prevents this by mounting a volume over
`temp/`; if you invoke `docker run` by hand, mount `ig-temp:/ig/temp` too.

**Packages re-download every run**: the `fhir-cache` volume isn't mounted. Note that
both SUSHI and the Publisher must agree on `$HOME`: the JVM resolves `user.home` from
`/etc/passwd`, not the environment, which is why the image runs as a real `fhir` user
rather than root.

**`Unable to read the git branch`**: harmless, the Publisher records provenance from
git. It disappears after `git init`.

**Broken links in `qa.html`**: usually a `menu:` entry in `sushi-config.yaml` with no
page behind it. Every menu item needs a generated or authored page.

**`EACCES` / `Failed to load <package>` after rebuilding the image**: a Docker volume
keeps the ownership it had when first populated, so caches written by an older
root-running image are unreadable to the current `fhir` user. Either recreate them
(`docker compose down -v`) or fix them in place:

```
docker run --rm -v hl7-irl-fhir-core_fhir-cache:/c alpine chown -R 1000:1000 /c
```

The same applies to generated directories on your disk. `AccessDeniedException:
/ig/template/.github` is the same problem: a root-era build created `template/` as
`root:root 755`, so the current user can't clear it. Delete `output/`,
`fsh-generated/` and `template/` once from the host and let the build recreate them.

**`Error parsing .../packages/<id>#<ver>#package/package/.index.json`**: the FHIR
package cache has a half-written entry, which is what interrupting a build mid-download
leaves behind. The cache is pure derived data, so delete the volume and let it refill:

```
docker volume rm hl7-irl-fhir-core_fhir-cache
```

**Out of memory**: raise `JAVA_OPTS=-Xmx8g`, and check Docker Desktop's VM has more
memory than that (Settings → Resources).

**Output owned by root (Linux only)**: the container runs as uid 1000. If your host
uid differs, add `--user "$(id -u):$(id -g)"`; `$HOME` inside the image is
world-writable so the caches still work.
