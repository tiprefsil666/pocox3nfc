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
