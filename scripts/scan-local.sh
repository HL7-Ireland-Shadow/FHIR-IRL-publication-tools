#!/usr/bin/env bash
#
# Runs the same Trivy scans as .github/workflows/docker-publish.yml, locally, so
# problems are caught before `git push`.
#
#   scripts/scan-local.sh                 repo secrets + build image + image vulns + image secrets
#   scripts/scan-local.sh --no-image      repo secret scan only (fast, no Docker build)
#   scripts/scan-local.sh --install-hook  install this as a git pre-push hook
#
# Uses a local `trivy` if installed, otherwise runs the aquasec/trivy image via Docker.
# Exit status is non-zero if any gate fails (same gates as CI):
#   - fixable CRITICAL vulnerabilities in the image
#   - HIGH/CRITICAL secrets in the repo or in the image
set -euo pipefail

# Keep in step with the trivy version used by aquasecurity/trivy-action in the workflow.
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.57.1}"
IMAGE_TAG="${IMAGE_TAG:-fhir-tools:scan}"

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

scan_image=1
for arg in "$@"; do
  case "${arg}" in
    --no-image) scan_image=0 ;;
    --install-hook)
      hook="$(git rev-parse --git-path hooks/pre-push)"
      if [[ -e "${hook}" ]] && ! grep -q "scripts/scan-local.sh" "${hook}"; then
        echo "scan-local: ${hook} already exists; not overwriting it." >&2
        exit 1
      fi
      printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/scan-local.sh"\n' > "${hook}"
      chmod +x "${hook}"
      echo "Installed pre-push hook at ${hook} (bypass once with: git push --no-verify)"
      exit 0
      ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "scan-local: unknown option ${arg}" >&2; exit 2 ;;
  esac
done

# --- pick a trivy runner ------------------------------------------------------------
# The image scan needs the Docker socket when trivy runs in a container.
if command -v trivy >/dev/null 2>&1; then
  trivy_cmd() { trivy "$@"; }
else
  command -v docker >/dev/null 2>&1 || { echo "scan-local: need trivy or docker installed." >&2; exit 2; }
  docker info >/dev/null 2>&1 || { echo "scan-local: Docker is not running." >&2; exit 2; }
  mkdir -p "${HOME}/.cache/trivy"
  trivy_cmd() {
    # MSYS_NO_PATHCONV stops Git Bash rewriting the container-side paths on Windows.
    MSYS_NO_PATHCONV=1 docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "${repo_root}:/src:ro" \
      -v "${HOME}/.cache/trivy:/root/.cache/trivy" \
      -w /src "${TRIVY_IMAGE}" "$@"
  }
fi

failed=0
step() { printf '\n==> %s\n' "$1"; }
gate() { # gate <description> <command...>
  local desc="$1"; shift
  if "$@"; then echo "PASS: ${desc}"; else echo "FAIL: ${desc}" >&2; failed=1; fi
}

step "Repository secrets (HIGH/CRITICAL)"
gate "repository secret scan" \
  trivy_cmd fs --scanners secret --severity HIGH,CRITICAL --exit-code 1 .

if [[ "${scan_image}" == 1 ]]; then
  step "Building image ${IMAGE_TAG}"
  docker build -t "${IMAGE_TAG}" docker

  step "Image vulnerabilities (fixable CRITICAL)"
  gate "image vulnerability scan" \
    trivy_cmd image --scanners vuln --severity CRITICAL --ignore-unfixed \
      --vuln-type os,library --exit-code 1 "${IMAGE_TAG}"

  step "Image secrets (HIGH/CRITICAL)"
  gate "image secret scan" \
    trivy_cmd image --scanners secret --severity HIGH,CRITICAL --exit-code 1 "${IMAGE_TAG}"
fi

echo
if [[ "${failed}" == 0 ]]; then echo "All scans passed."; else echo "One or more scans FAILED." >&2; fi
exit "${failed}"
