#!/usr/bin/env bash
# Check the host before anything else.
#
# The build needs a chroot with an arm64 cross toolchain, and it needs a
# handful of tools that are easy to forget. This lists what is missing and
# how to install it, instead of failing three minutes into a build.
#
#   ./00-check-host.sh          report only
#   ./00-check-host.sh --install  also print the apt line
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

SHOW_INSTALL=${1:-}

# name | why it is needed | apt package
#
# The first field is the COMMAND to look for, not the package name: on
# Debian, e2fsprogs provides mkfs.ext4, device-tree-compiler provides
# dtc, and so on. The third field is the package to install.
REQUIRED="
git|the pmaports checkout|git
python3|the pmbootstrap driver|python3
bc|post-install scripts in the chroot|bc
flex|the kernel build|flex
bison|the kernel build|bison
cpio|the kernel build|cpio
rsync|the pmbootstrap file sync|rsync
make|the kernel build|make
gcc|the chroot native build|gcc
clang|the kernel build|clang
lld|the kernel link step|lld
llvm-config|the kernel build|llvm
mkfs.ext4|mkfs.ext4 for the rootfs|e2fsprogs
mkfs.fat|the boot partition|dosfstools
dtc|the device tree|device-tree-compiler
zstd|the kernel source archive|zstd
openssl|the kernel signing keys|openssl
kpartx|loop device mapping for pmbootstrap|kpartx
parted|partition tables|parted
sgdisk|GPT partitioning|sgdisk
fusermount3|mounting the pmbootstrap chroot|fuse3
qemu-aarch64-static|arm64 binaries in the chroot|qemu-user-static
arch-test|pmbootstrap's own test suite|arch-test
"

# Tools that are nice to have: they are not needed for the build itself, but
# they are needed to check the result afterwards.
OPTIONAL="
fastboot|flashing the phone|android-sdk-fastboot
adb|talking to the phone|android-tools
simg2img|inspecting the factory images|android-sdk-libsparse-utils
"

missing=""
present=""

check() {
    local list=$1 kind=$2
    local name why pkg
    while IFS='|' read -r name why pkg; do
        [ -n "$name" ] || continue
        if which_of "$name" >/dev/null 2>&1; then
            present="$present $name"
            [ "$kind" = required ] && ok "$name — $why"
        else
            if [ "$kind" = required ]; then
                missing="$missing $name"
                printf '%sFALTA%s %-20s %s\n' "$C_RED" "$C_RESET" "$name" "$why"
            else
                printf '%sopcional%s %-16s %s\n' "$C_YELLOW" "$C_RESET" "$name" "$why"
            fi
        fi
    done <<< "$list"
}

say "A verificar o host"
echo

check "$REQUIRED" required
echo
check "$OPTIONAL" optional
echo

if [ -n "$missing" ]; then
    printf '%sFaltam %s:%s\n' "$C_RED" "$C_RESET" "$missing"
    # Turn the list into apt package names.
    pkgs=""
    for n in $missing; do
        p=$(grep "^$n|" <<< "$REQUIRED" | cut -d'|' -f3)
        pkgs="$pkgs $p"
    done
    echo
    echo "Para instalar:"
    echo "    sudo apt install $pkgs"
    [ "$SHOW_INSTALL" = "--install" ] && echo
    exit 1
fi

ok "todas as dependências estão presentes"

# A few things that are not packages but still bite.
echo
say "Outras verificações"

if [ "$(id -u)" -eq 0 ]; then
    warn "a correr como root — o pmbootstrap prefere um utilizador normal com sudo"
else
    ok "utilizador normal (o pmbootstrap usa sudo)"
fi

if ! which_of sudo >/dev/null 2>&1; then
    die "sem sudo — o pmbootstrap precisa dele para montar o chroot"
fi
ok "sudo disponível"

# A 64-bit host is needed to run the arm64 chroot binaries.
if [ "$(uname -m)" = "x86_64" ]; then
    ok "host x86_64 (com qemu-user-static para o arm64)"
else
    warn "host $(uname -m) — a emulação qemu não é necessária, mas o pmbootstrap pode não suportar"
fi

# The space the build needs. A rootfs, a chroot, and the kernel build.
avail=$(df -BG --output=avail "$PROJECT" 2>/dev/null | tail -1 | tr -dc '0-9')
if [ -n "$avail" ] && [ "$avail" -lt 30 ]; then
    warn "só ${avail}G livres em $PROJECT — o build precisa de ~30G"
else
    ok "${avail:-?}G livres em $PROJECT"
fi

# The git identity, needed by `git am` inside the kernel build.
if ! git config --get user.email >/dev/null 2>&1; then
    warn "sem git user.email — o build da série de patches pode falhar"
    echo "    git config --global user.email \"you@example.com\""
    echo "    git config --global user.name  \"Your Name\""
else
    ok "identidade do git configurada"
fi

echo
ok "o host está pronto"
