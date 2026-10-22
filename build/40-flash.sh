#!/usr/bin/env bash
# Flash the built image onto the phone.
#
#   ./40-flash.sh            show what would be done
#   ./40-flash.sh --run      do it
#
# IMPORTANT: do this on a second partition, on a second phone, or on a
# microSD card first. The phone that works today is not a good test subject.
set -eu
. "$(dirname -- "$0")/env.sh"
. "$(dirname -- "$0")/lib.sh"

RUN=${1:-}

IMAGES=$WORK/images
[ -d "$IMAGES" ] || die "não há imagens em $IMAGES — corra 30-build.sh primeiro"

BOOTDIR=$PROJECT/postmarketos/prebuilt

# The two panels. The POCO X3 NFC shipped with a Huaxing and a Tianma
# display, and a black screen after flashing almost always means the wrong
# u-boot or the wrong device tree — not a bricked phone.
PANEL=${PANEL:-huaxing}
UBOOT=${UBOOT:-$BOOTDIR/u-boot-sm7150-xiaomi-surya-$PANEL.img}

say "o que vai ser feito"
cat <<EOF

  1. entrar em fastboot          adb reboot bootloader
  2. apagar o dtbo               fastboot erase dtbo
  3. gravar o u-boot             fastboot flash boot u-boot-sm7150-xiaomi-surya-$PANEL.img
  4. gravar a raiz               pmbootstrap flasher flash_rootfs
  5. arrancar                    fastboot reboot

  (o vbmeta vazio é opcional — ver a nota abaixo)

EOF

cat <<'EOF'
📌 Isto é o procedimento oficial, da wiki do projecto:

    https://wiki.nura.eco/wiki/Qualcomm_SM7150_(qcom-sm7150)

  O U-Boot é *chainloaded* pelo bootloader de fábrica: o bootloader
  primário não é substituído, o U-Boot vai para a partição "boot" e a
  Xiaomi arranca-o. A raiz vai para "userdata".

  O esquema de partições mudou completamente com a passagem para o
  U-Boot. O esquema antigo e o novo são incompatíveis e não há migração:
  é uma instalação limpa ou nada.

EOF

say "imagens disponíveis"
ls -lh "$IMAGES" 2>/dev/null || true
echo

if [ ! -f "$UBOOT" ]; then
    warn "u-boot não encontrado em $UBOOT"
    echo "    o u-boot tem de ser o do painel $PANEL; um painel errado dá ecrã preto"
    echo "    PANEL=tianma ./40-flash.sh para tentar o outro"
    echo
fi

# Which panel is this phone? The wiki's method, which is better than
# reading a property: the kernel logs it.
echo "  Para confirmar o painel, com o Android a correr:"
echo "      adb wait-for-device && adb reboot && adb logcat | grep \"panel name is\""
echo "      # imprime 'panel name is Huaxing' ou 'panel name is Tianma'"
echo

if [ "$RUN" != "--run" ]; then
    say "isto foi só a pré-visualização"
    echo "    corra com --run para gravar, ou leia surya-pmos/README.md"
    exit 0
fi

which_of fastboot >/dev/null 2>&1 || die "sem fastboot no PATH"
which_of adb >/dev/null 2>&1 || die "sem adb no PATH"

say "a entrar em fastboot"
adb devices || true
adb reboot bootloader
sleep 5

say "a gravar o u-boot"
fastboot flash boot "$UBOOT"

say "a apagar o dtbo"
fastboot erase dtbo

# The vbmeta is optional. The wiki does not mention it: with the bootloader
# unlocked and U-Boot chainloaded, the AVB verification is not enforced.
# Flashing it does no harm, and it is the guarantee — so it is done, but
# a failure is not fatal.
say "a gravar o vbmeta vazio (opcional)"
for f in vbmeta vbmeta_system; do
    if [ -f "$BOOTDIR/$f.img" ]; then
        fastboot flash "$f" "$BOOTDIR/$f.img" --disable-verity --disable-verification \
            || warn "o $f não foi gravado — é opcional"
    else
        warn "$f.img não está em $BOOTDIR — corra 05-prepare-boot.sh"
    fi
done

say "a gravar a raiz"
$PMB flasher flash_rootfs

say "a arrancar"
fastboot reboot

ok "a preguntar. As primeiras 30 s são lentas; o primeiro arranque é sempre demorado."
echo
echo "Se o ecrã ficar preto, não é um brick: é o u-boot ou a device tree errados."
echo "Voltar ao Android:"
echo "    fastboot flash boot boot.img    # a partir do pacote de firmware da Xiaomi"
echo "    fastboot reboot"
