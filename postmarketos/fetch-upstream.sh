#!/bin/sh
set -eu

cd "$(dirname "$0")"
mkdir -p upstream

clone_if_missing() {
	url=$1
	dest=$2
	if [ -d "$dest/.git" ]; then
		git -C "$dest" pull --ff-only
	else
		git clone --depth=1 "$url" "$dest"
	fi
}

# The requested SM7150 package source first, then official and device-specific references.
clone_if_missing https://github.com/sm7150-mainline/postmarketos.git upstream/sm7150-mainline-postmarketos
clone_if_missing https://gitlab.postmarketos.org/postmarketOS/pmaports.git upstream/pmaports
clone_if_missing https://github.com/woodyst/surya-pmos.git upstream/surya-pmos

# pmbootstrap itself, pinned to the version the build was written against.
# Its 3.12.1 `init` is interactive, which is why build/30-build.sh writes
# the configuration directly instead of answering it.
if [ ! -d pmbootstrap/.git ]; then
    git clone --depth=1 --branch 3.12.1 \
        https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git pmbootstrap
fi
