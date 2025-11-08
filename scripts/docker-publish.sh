#!/usr/bin/env bash
set -euo pipefail

# Build and push Docker images for microservices to Docker Hub.
# By default this runs in DRY RUN mode (prints what it would do).
# Use --execute to actually build and push.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

SERVICES=(
  cart-service
  catalog-service
  inventory-service
  notification-service
  order-service
  payment-service
  recommendation-service
)

DOCKERHUB_USER=""
TAG=""
SELECTED_SERVICE=""
ALL=0
EXECUTE=0
LOGIN=0
ALSO_LATEST=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -u, --user USER         Docker Hub username/namespace (e.g. davidlondo) [required]
  -t, --tag TAG           Image tag to use (default: dev-<git-sha>)
  -s, --service NAME      Only build/push a single microservice by name
  -a, --all               Build/push all microservices (default if --service not provided)
      --execute           Actually run docker build/push (default is dry-run)
      --login             Perform 'docker login' before pushing (uses DOCKERHUB_TOKEN if set)
      --also-latest       Also tag and push ':latest' alongside the specified tag
  -h, --help              Show this help

Examples:
  # Dry-run all services (prints commands only)
  $(basename "$0") --user davidlondo --all

  # Build+push a single service with a custom tag
  $(basename "$0") -u davidlondo -s cart-service -t v0.1.0 --execute

  # Build+push all with default tag dev-<gitsha> and also tag as latest
  $(basename "$0") -u davidlondo --all --execute --also-latest
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user) DOCKERHUB_USER="$2"; shift 2;;
    -t|--tag) TAG="$2"; shift 2;;
    -s|--service) SELECTED_SERVICE="$2"; shift 2;;
    -a|--all) ALL=1; shift;;
    --execute) EXECUTE=1; shift;;
    --login) LOGIN=1; shift;;
    --also-latest) ALSO_LATEST=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" && usage && exit 1;;
  esac
done

if [[ -z "$DOCKERHUB_USER" ]]; then
  echo "ERROR: --user is required (your Docker Hub username/namespace)"
  usage
  exit 1
fi

if [[ -z "$TAG" ]]; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    SHA=$(git rev-parse --short HEAD)
  else
    SHA="local"
  fi
  TAG="dev-$SHA"
fi

run() {
  echo "+ $*"
  if [[ "$EXECUTE" -eq 1 ]]; then
    eval "$@"
  fi
}

do_login() {
  if [[ "$LOGIN" -eq 1 ]]; then
    if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
      echo "$DOCKERHUB_TOKEN" | run docker login -u "$DOCKERHUB_USER" --password-stdin
    else
      echo "INFO: DOCKERHUB_TOKEN not set; will run interactive docker login" >&2
      run docker login -u "$DOCKERHUB_USER"
    fi
  fi
}

resolve_services() {
  local list=()
  if [[ -n "$SELECTED_SERVICE" ]]; then
    list=("$SELECTED_SERVICE")
  else
    list=("${SERVICES[@]}")
  fi
  echo "${list[@]}"
}

validate_service() {
  local svc="$1"
  if [[ ! -f "microservices/$svc/Dockerfile" ]]; then
    echo "WARN: microservices/$svc/Dockerfile not found; skipping" >&2
    return 1
  fi
  return 0
}

build_and_push() {
  local svc="$1"
  local context="microservices/$svc"
  local image="$DOCKERHUB_USER/$svc:$TAG"

  validate_service "$svc" || return 0

  run docker build -t "$image" "$context"
  run docker push "$image"

  if [[ "$ALSO_LATEST" -eq 1 ]]; then
    local latest="$DOCKERHUB_USER/$svc:latest"
    run docker tag "$image" "$latest"
    run docker push "$latest"
  fi
}

main() {
  if [[ -n "$SELECTED_SERVICE" && "$ALL" -eq 1 ]]; then
    echo "ERROR: specify either --service or --all, not both" >&2
    exit 1
  fi

  if [[ -z "$SELECTED_SERVICE" && "$ALL" -eq 0 ]]; then
    # default to all
    ALL=1
  fi

  echo "Repo root: $REPO_ROOT"
  echo "Docker Hub user: $DOCKERHUB_USER"
  echo "Tag: $TAG"
  echo "Mode: $([[ "$EXECUTE" -eq 1 ]] && echo RUN || echo DRY-RUN)"

  do_login

  local targets=()
  IFS=' ' read -r -a targets <<< "$(resolve_services)"

  for svc in "${targets[@]}"; do
    build_and_push "$svc"
  done

  echo "Done."
  if [[ "$EXECUTE" -eq 0 ]]; then
    echo "Note: This was a dry run. Add --execute to actually build and push images."
  fi
}

main "$@"
