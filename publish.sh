#!/bin/sh
# Build the nettest-portable image for several CPU architectures and push it to
# Docker Hub as <DOCKERHUB_USER>/nettest-portable.
#
# Usage:
#   docker login                       # once
#   DOCKERHUB_USER=yourname ./publish.sh
#
# Environment (or put DOCKERHUB_USER in .env):
#   DOCKERHUB_USER  Docker Hub account or organization (required)
#   IMAGE_NAME      repository name             (default: nettest-portable)
#   PLATFORMS       target platforms            (default: linux/arm64,linux/amd64)
#   CUTIE_REF       Cutie branch/tag to build   (default: main)
#   CRUSADER_VERSION Crusader release tag       (default: v0.3.2)
#   PUSH            set to 0 to build without pushing (test run)
#   NO_CACHE        set to 1 to rebuild everything (fresh Cutie checkout,
#                   latest Ubuntu packages) instead of reusing cached layers
set -eu

cd "$(dirname "$0")"

# Pick up DOCKERHUB_USER etc. from .env if not already set
if [ -f .env ]; then
	set -a
	# shellcheck disable=SC1091
	. ./.env
	set +a
fi

: "${DOCKERHUB_USER:?Set DOCKERHUB_USER to your Docker Hub user name}"
IMAGE_NAME="${IMAGE_NAME:-nettest-portable}"
PLATFORMS="${PLATFORMS:-linux/arm64,linux/amd64}"
CUTIE_REF="${CUTIE_REF:-main}"
CRUSADER_VERSION="${CRUSADER_VERSION:-v0.3.2}"
PUSH="${PUSH:-1}"
NO_CACHE="${NO_CACHE:-0}"

REPO="docker.io/${DOCKERHUB_USER}/${IMAGE_NAME}"
VERSION="$(date -u +%Y%m%d)"

# Multi-platform builds need a docker-container builder (the default
# "docker" driver can only build for one platform at a time).
BUILDER=nettest-builder
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
	docker buildx create --name "$BUILDER" --driver docker-container >/dev/null
fi

if [ "$PUSH" = 1 ]; then
	output="--push"
	echo "Building ${PLATFORMS} and pushing ${REPO}:latest and ${REPO}:${VERSION}"
else
	output=""   # build only; result stays in the builder cache
	echo "Test build of ${PLATFORMS} (not pushing)"
fi

cache=""
if [ "$NO_CACHE" = 1 ]; then
	cache="--no-cache --pull"
fi

# shellcheck disable=SC2086
docker buildx build \
	--builder "$BUILDER" \
	--platform "$PLATFORMS" \
	--build-arg IMAGE_VERSION="$VERSION" \
	--build-arg CUTIE_REF="$CUTIE_REF" \
	--build-arg CRUSADER_VERSION="$CRUSADER_VERSION" \
	--tag "${REPO}:latest" \
	--tag "${REPO}:${VERSION}" \
	$output \
	$cache \
	.

if [ "$PUSH" = 1 ]; then
	echo "Published ${REPO}:latest and ${REPO}:${VERSION}"
	echo "On the board: put NETTEST_IMAGE=${DOCKERHUB_USER}/${IMAGE_NAME}:latest in .env, then"
	echo "  docker compose pull && docker compose up -d"
fi
