#!/usr/bin/env bash
#
# Build and push the K8Shop Load Generator Docker image
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-davidlondo/k8shop-load-generator}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# Parse command line arguments
BUILD_ONLY=false
PUSH_ONLY=false
NO_CACHE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --push-only)
            PUSH_ONLY=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --build-only    Only build the image, don't push"
            echo "  --push-only     Only push the image, don't build"
            echo "  --no-cache      Build without using cache"
            echo "  --tag TAG       Specify image tag (default: latest)"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# Build the image
if [[ "$PUSH_ONLY" == "false" ]]; then
    log_info "Building Docker image: $FULL_IMAGE"
    
    BUILD_ARGS=(
        -t "$FULL_IMAGE"
        -f "$DOCKERFILE"
    )
    
    if [[ "$NO_CACHE" == "true" ]]; then
        BUILD_ARGS+=(--no-cache)
    fi
    
    BUILD_ARGS+=(.)
    
    if docker build "${BUILD_ARGS[@]}"; then
        log_info "✓ Image built successfully: $FULL_IMAGE"
    else
        log_error "Failed to build image"
        exit 1
    fi
    
    # Show image size
    IMAGE_SIZE=$(docker images "$FULL_IMAGE" --format "{{.Size}}")
    log_info "Image size: $IMAGE_SIZE"
fi

# Push the image
if [[ "$BUILD_ONLY" == "false" ]]; then
    log_info "Pushing image to registry: $FULL_IMAGE"
    
    if docker push "$FULL_IMAGE"; then
        log_info "✓ Image pushed successfully: $FULL_IMAGE"
    else
        log_error "Failed to push image"
        log_warn "Make sure you're logged in: docker login"
        exit 1
    fi
fi

# Summary
echo ""
log_info "=== Summary ==="
log_info "Image: $FULL_IMAGE"
if [[ "$BUILD_ONLY" == "false" && "$PUSH_ONLY" == "false" ]]; then
    log_info "Built and pushed successfully!"
elif [[ "$BUILD_ONLY" == "true" ]]; then
    log_info "Built successfully (not pushed)"
elif [[ "$PUSH_ONLY" == "true" ]]; then
    log_info "Pushed successfully (not built)"
fi

echo ""
log_info "Next steps:"
if [[ "$BUILD_ONLY" == "true" ]]; then
    echo "  - Run: docker push $FULL_IMAGE"
fi
echo "  - Deploy with: kubectl apply -f k8s/load-generator-master.yaml"
echo "  - Or using Helm: helm upgrade --install bookstore ../helm/bookstore --set loadGenerator.enabled=true"
echo "  - Access UI with: kubectl port-forward -n bookstore svc/load-generator 8089:8089"
