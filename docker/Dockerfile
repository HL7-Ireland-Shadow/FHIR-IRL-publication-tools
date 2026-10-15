# syntax=docker/dockerfile:1
#
# HL7 FHIR IG publishing toolchain.
#
# Everything needed to take a SUSHI/FSH project all the way to a rendered IG:
#   - JDK (runs the IG Publisher and the FHIR Validator)
#   - HL7 FHIR IG Publisher (publisher.jar)
#   - HL7 FHIR Validator (validator_cli.jar)
#   - Node.js + SUSHI (FSH -> FHIR) + GoFSH (FHIR -> FSH)
#   - Ruby + Jekyll (the IG Publisher shells out to Jekyll to render pages; compilers are
#     used only while installing the gems, then purged)
#   - Graphviz (dot, used by the Publisher's PlantUML diagram rendering)
#   - git / curl / unzip / jq / python3 (IG templates and helper scripts expect them)

ARG JAVA_VERSION=21
FROM eclipse-temurin:${JAVA_VERSION}-jre-noble

# Tool versions, all pinned so every build of this repo is reproducible and reviewable.
# Versions below were checked against the upstream release pages on 2026-10-15:
#   IG Publisher  https://github.com/HL7/fhir-ig-publisher/releases
#   Validator     https://github.com/hapifhir/org.hl7.fhir.core/releases
#   SUSHI/GoFSH   https://www.npmjs.com/package/fsh-sushi, https://www.npmjs.com/package/gofsh
#   Bundler       https://rubygems.org/gems/bundler
# The JARs are verified against the sha256 below (the digest GitHub publishes for the
# release asset). To upgrade, change the version AND its sha256 together; the build
# fails if they don't match.
ARG IG_PUBLISHER_VERSION=3.0.0
ARG IG_PUBLISHER_SHA256=b8403abe5a438ddb9a3a07e02ad925f2c4bbbd9e903c49ecff50fcb481ec64ad
ARG VALIDATOR_VERSION=7.0.1
ARG VALIDATOR_SHA256=1178b6a3a3fe98d9cd9545cadee505274967332466001d857e4d8bed7138a5bc
ARG SUSHI_VERSION=3.21.0
ARG GOFSH_VERSION=2.6.1
ARG BUNDLER_VERSION=4.0.23
ARG JEKYLL_VERSION=4.3.4
ARG NODE_MAJOR=22

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    FHIR_HOME=/opt/fhir \
    HOME=/home/fhir \
    IG_DIR=/ig

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg git jq unzip zip xz-utils \
        graphviz \
        ruby \
        python3 \
        fonts-dejavu-core tzdata  \
    && rm -rf /var/lib/apt/lists/*

# Node.js (NodeSource) - SUSHI needs a current LTS.
# Installed from NodeSource's signed apt repo (key + sources entry, then apt-get) rather
# than piping their setup script into a shell.
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Jekyll: the IG Publisher invokes `jekyll build` to render the HTML pages.
# Jekyll's em-websocket dependency pulls in C extensions (eventmachine, http_parser.rb)
# that have no prebuilt gems, so a toolchain is needed to INSTALL it but not to run it.
# It is installed and purged in this one layer so the compilers never reach the image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ruby-dev build-essential zlib1g-dev \
    && gem install --no-document "bundler:${BUNDLER_VERSION}" "jekyll:${JEKYLL_VERSION}" \
    && apt-get purge -y --auto-remove ruby-dev build-essential zlib1g-dev \
    && find / -xdev \( -name gem_make.out -o -name mkmf.log -o -name '*.o' \) -path '*gems*' -delete \
    && rm -rf /var/lib/apt/lists/* /root/.gem

# Guard the purge: no compilers left, and the compiled gems still load (this would catch
# a runtime library having been auto-removed along with the build tools).
RUN ! command -v gcc && ! command -v cc && ! command -v make \
    && ruby -e 'require "eventmachine"; require "http/parser"' \
    && d="$(mktemp -d)" \
    && printf -- '---\n---\na { b: c }\n' > "${d}/s.scss" \
    && echo hello > "${d}/index.md" \
    && jekyll build -s "${d}" -d "${d}/_site" >/dev/null \
    && rm -rf "${d}"

# SUSHI compiles FSH; GoFSH decompiles existing FHIR back to FSH.
# --ignore-scripts: don't run dependencies' install hooks as root at build time. Neither
# package defines one itself; `sushi --version` in record-versions below fails the build
# if a dependency turns out to need one.
RUN npm install -g --ignore-scripts "fsh-sushi@${SUSHI_VERSION}" "gofsh@${GOFSH_VERSION}" \
    && npm cache clean --force

# IG Publisher + Validator jars: exact release, sha256-verified.
RUN set -euo pipefail; mkdir -p "${FHIR_HOME}"; \
    curl -fsSL --retry 3 -o "${FHIR_HOME}/publisher.jar" \
        "https://github.com/HL7/fhir-ig-publisher/releases/download/${IG_PUBLISHER_VERSION}/publisher.jar"; \
    curl -fsSL --retry 3 -o "${FHIR_HOME}/validator_cli.jar" \
        "https://github.com/hapifhir/org.hl7.fhir.core/releases/download/${VALIDATOR_VERSION}/validator_cli.jar"; \
    echo "${IG_PUBLISHER_SHA256}  ${FHIR_HOME}/publisher.jar" | sha256sum -c -; \
    echo "${VALIDATOR_SHA256}  ${FHIR_HOME}/validator_cli.jar" | sha256sum -c -

COPY fhir-tools /usr/local/bin/fhir-tools
COPY record-versions.sh /usr/local/bin/record-versions

# Record exactly what landed in the image (surfaced by `fhir-tools versions`).
RUN chmod +x /usr/local/bin/fhir-tools /usr/local/bin/record-versions && record-versions

# A real passwd entry is required, not just $HOME: SUSHI (Node) reads $HOME, but the
# JVM resolves user.home from /etc/passwd, so running as root cached packages to
# /root/.fhir - outside the mounted volume - while SUSHI used $HOME. One user, one cache.
#
# Dirs are world-writable so the container also runs as `--user $(id -u):$(id -g)` on
# Linux hosts (keeping bind-mounted output owned by the invoking user), and so named
# volumes mounted over temp/ and input-cache/ inherit writable ownership.
#
# Some base image builds already ship a uid/gid 1000 account (e.g. `ubuntu`); rename it to
# `fhir` rather than failing, and create it only when the base doesn't have one.
RUN g="$(getent group 1000 | cut -d: -f1 || true)"; \
    u="$(getent passwd 1000 | cut -d: -f1 || true)"; \
    if [ -z "$g" ]; then groupadd --gid 1000 fhir; \
    elif [ "$g" != "fhir" ]; then groupmod --new-name fhir "$g"; fi; \
    if [ -z "$u" ]; then useradd --uid 1000 --gid 1000 --home-dir "${HOME}" --shell /bin/bash fhir; \
    else usermod --login fhir --home "${HOME}" --gid 1000 --shell /bin/bash "$u"; fi \
    && mkdir -p "${HOME}/.fhir" "${IG_DIR}/temp" "${IG_DIR}/input-cache" \
    && chown -R fhir:fhir "${HOME}" "${IG_DIR}" \
    && chmod -R 777 "${HOME}" "${IG_DIR}"

# Mount named volumes at $HOME/.fhir (FHIR package + IG template cache) and over
# temp/ + input-cache/ (see docker-compose.yml). The scratch dirs MUST NOT sit on a
# Windows/macOS bind mount: the Publisher writes SQLite into temp/ and the host
# filesystem driver corrupts it (SQLITE_CORRUPT in DBBuilder).
USER fhir
WORKDIR /ig

ENTRYPOINT ["/usr/local/bin/fhir-tools"]
CMD ["publish"]
