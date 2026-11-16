#!/bin/sh
# Build the nettest-portable image for several CPU architectures and push it to
# Docker Hub as <DOCKERHUB_USER>/nettest-portable.
#
# Versioning: the release version lives in ABOUT.md, on a line like
#   _Version 0.1.0 - 14Nov2026_
# Every push bumps the last number by one (0.1.0 -> 0.1.1) and sets today's
# date, then builds (ABOUT.md is baked into the image) and tags the image
# with both "latest" and the version. If the build fails, ABOUT.md is put
# back as it was. Commit the updated ABOUT.md afterwards.
# A test build (PUSH=0) doesn't change the version.
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

# --- Version (from ABOUT.md) ------------------------------------------------
VERSION_RE='^_Version [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]* - [0-9A-Za-z]*_$'
version_line="$(grep -E "$VERSION_RE" ABOUT.md || true)"
if [ -z "$version_line" ] || [ "$(printf '%s\n' "$version_line" | wc -l)" -ne 1 ]; then
	echo "ABOUT.md must contain exactly one line like: _Version 0.1.0 - 14Nov2026_" >&2
	exit 1
fi
VERSION="$(printf '%s\n' "$version_line" | sed -E 's/^_Version ([0-9.]+) - .*/\1/')"

if [ "$PUSH" = 1 ]; then
	major="${VERSION%%.*}"; rest="${VERSION#*.}"
	minor="${rest%%.*}";    patch="${rest#*.}"
	VERSION="${major}.${minor}.$((patch + 1))"
	day="$(date +%d)"; day="${day#0}"
	DATE="${day}$(LC_ALL=C date +%b%Y)"          # e.g. 15Nov2026

	cp ABOUT.md ABOUT.md.publish-bak
	restore_about() {
		if [ -f ABOUT.md.publish-bak ]; then
			mv ABOUT.md.publish-bak ABOUT.md
			echo "Build failed: ABOUT.md restored (version not bumped)" >&2
		fi
	}
	trap restore_about EXIT
	trap 'exit 130' INT TERM
	sed -E "s/^_Version [0-9.]+ - [0-9A-Za-z]*_\$/_Version ${VERSION} - ${DATE}_/" \
		ABOUT.md.publish-bak > ABOUT.md
	echo "Version ${VERSION} - ${DATE} (written to ABOUT.md)"
fi

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
	echo "Test build of ${PLATFORMS}, version ${VERSION} (not pushing)"
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
	rm -f ABOUT.md.publish-bak      # success: keep the bumped ABOUT.md
	echo "Published ${REPO}:latest and ${REPO}:${VERSION}"
	echo "Commit the new version:  git commit -m 'Release ${VERSION}' ABOUT.md"
	echo "On the board:            docker compose pull && docker compose up -d"
fi
