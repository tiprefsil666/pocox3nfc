# Shared settings for the build scripts.
#
# Sourced by every script in this directory. Change the values here, not in
# the scripts.
#
#   PROJECT   the repository root (the parent of this directory)
#   PMB       the pmbootstrap command
#   PMAPORTS  the pmaports checkout the overlays are copied into
#   WORK      the pmbootstrap working directory
#   OUT       where the build logs and the image manifest land

PROJECT=${PROJECT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
BUILD=$PROJECT/build

# The pmbootstrap checkout. 3.12.1 is the version this was written against:
# its `init` is interactive, so the configuration is written directly into
# a project-local file instead — see 30-build.sh.
PMB_SRC=${PMB_SRC:-$PROJECT/postmarketos/pmbootstrap}

# The project-local configuration file. Using our own keeps this project
# from disturbing another pmbootstrap work, and records the settings of
# the build alongside it.
PMB_CFG=${PMB_CFG:-$BUILD/out/pmbootstrap_v3.cfg}

# The pmbootstrap command. The config file is passed with -c, which this
# version accepts as a global option.
PMB=${PMB:-sudo python3 $PMB_SRC/pmbootstrap.py -c $PMB_CFG}

# The pmaports checkout, and the pmbootstrap working directory. Both have to
# be absolute: pmbootstrap stores them in its configuration and uses them in
# every later command.
PMAPORTS=${PMAPORTS:-$PROJECT/postmarketos/upstream/pmaports}
WORK=${WORK:-$PROJECT/build-pmb}

# The target.
#
# Note: PMOS_HOSTNAME, not HOSTNAME. The shell already has a HOSTNAME
# variable — it is the name of the computer — and `${HOSTNAME:-surya}` would
# quietly keep the computer's name, putting that on the phone.
DEVICE=${DEVICE:-qcom-sm7150}
KERNEL=${KERNEL:-postmarketos-qcom-sm7150}
UI=${UI:-postmarketos-ui-plasma-mobile}
PMOS_HOSTNAME=${PMOS_HOSTNAME:-surya}
USER_NAME=${USER_NAME:-user}
TIMEZONE=${TIMEZONE:-Europe/Lisbon}
LOCALE=${LOCALE:-en_US.UTF-8}
KEYMAP=${KEYMAP:-nokeys}

# The pmaports commit the libcamera recipe was forked from.
#
# The overlay's APKBUILD is a fork of the pmaports recipe, with our two
# patches (0004 and 0005) on top of the three the distribution had at the
# time. The distribution has moved on since: it dropped the PinePhone
# patches, renamed the others, and changed the sensor tuning files — so the
# current pmaports does NOT satisfy the recipe's checksums, and the build
# would fail on the missing sources.
#
# 4b25f699 is "temp/libcamera: upgrade to 0.7.1", and it is the exact state
# the recipe was written against: the same three patches, the same tuning
# files, the same qcam.desktop, all with matching sha512sums.
LIBCAMERA_BASE=4b25f699e4c75682d29ae3ec60741e585e8d9342

# The four overlays that are copied over pmaports.
OVERLAY_KERNEL=linux-$KERNEL
OVERLAY_LIBCAMERA=libcamera
OVERLAY_LIBQMI=libqmi
OVERLAY_HEXAGON=hexagonrpcd

# Where the kernel package lives inside the pmaports checkout.
#
# This moves around: the layout used to be device/testing/, and the current
# pmaports has it in device/community/. Rather than hardcode it, 10-fetch.sh
# looks the package up and writes the answer here.
KERNEL_PKG_DIR=${KERNEL_PKG_DIR:-$PMAPORTS/device/community/$OVERLAY_KERNEL}

# Where the logs and the manifest go.
OUT=$BUILD/out
LOG=$OUT/logs
MANIFEST=$OUT/manifest.txt
