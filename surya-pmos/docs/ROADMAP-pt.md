# Próximos passos: da análise à build final testada

**Estado em 2026-10-20.** Este documento é o plano de trabalho a partir de agora.
Complementa o `README.md` (o que funciona), o `docs/pending.es.md` (a lista de
pendentes) e o `docs/deploy.es.md` (a receita de implantação já existente, em
espanhol).

> **O que separa o kit de estar demonstrado.** O kernel está verificado: os 140
> patches aplicam limpos, reproduzem o kernel implantado bit a bit e compilam.
> O que **nunca foi ensaiado** é a receita completa de ponta a ponta numa
> instalação limpa do postmarketOS. É isso que este plano ataca.

---

## Parte 1 — O que falta, por subsistema

### 1.1 Bloqueadores de build

| # | Bloqueador | Impacto | Como resolver |
|---|---|---|---|
| B1 | `pmaports` não está descarregado | **bloqueia tudo** | `postmarketos/fetch-upstream.sh` (ver §2.2) |
| B2 | `bc` não está instalado | falha a configuração do kernel | `sudo apt install bc` |
| B3 | Não somos root | `pmbootstrap` exige root para o chroot | `sudo` em todo o passo 3 |
| B4 | `pmbootstrap` não está no PATH | inconvenience | usar `python3 .../pmbootstrap.py` |
| B5 | A série de patches tem contadores incoerentes | `git am` falha se os índices não baterem | ver §4.3 — **isto é um bug real do repositório** |

### 1.2 Hardware que ainda não foi testado

| # | Item | Como testar | Critério de aceitação |
|---|---|---|---|
| H1 | **Carga rápida de 33 W** | carregador Xiaomi + `batterysecret` de produção | o `usbpd` marca `USB_HVDCP_3` e o `bq2597x` mostra o limite elevado |
| H2 | **NFC** | encostar uma etiqueta | o `nfc` do mainline lê a etiqueta; hoje **não há driver** |
| H3 | **Câmara frontal** (S5K3T2) | `pipewire` + `gst-launch` | sem pacotes, sem erro; hoje não há fluxo |
| H4 | **Câmara de profundidade** (GC02M1B, OV02B1B) | idem | idem |
| H5 | **A-GPS** | frio, ao ar livre | fix em <30 s; hoje o fix frio é lento |
| H6 | **USB OTG** com teclado | ligar um teclado USB | o teclado escreve no terminal |
| H7 | **Auriculares por cabo** (USB-C) | ligar auscultadores | audio bidireccional |
| H8 | **Slot SIM 2** | inserir um segundo SIM | o modem detecta-a |
| H9 | **TV-out** (via USB-C) | ligar um ecrã | não testado em lado nenhum |
| H10 | **IR de controlo remoto** | ver [`rea/02-notes/ir-and-fm.md`](../../rea/02-notes/ir-and-fm.md) | ⚠️ **o firmware sugere que não existe** — confirmar fisicamente antes de escrever código |
| H11 | **IR da câmara + filtro IR-cut** | abrir a câmara no escuro | o filtro muda de estado, a câmara vê em IR |
| H12 | **Rádio FM** | ligar auscultadores, abrir a app de rádio | ⚠️ **todo o stack falta no mainline** |

### 1.3 Software que falta escrever

| # | Falta | Esforço | Prioridade |
|---|---|---|---|
| S1 | **Driver NFC** (PN557) | grande | baixa — a NFC é um extra |
| S2 | **Handshake de carregamento rápido** | médio | **média** — precisa do `usbpd` do mainline |
| S3 | **Driver do amplificador TAS2562** | já existe (patches 0013–0016, 0022–0027) | — |
| S4 | **Roteamento de microfones** do WCD9375 | pequeno | **alta** — está no `mixer_paths` |
| S5 | **A-GPS no modem** | médio | média |
| S6 | **Portar o `mixer_paths` para mainline** | pequeno | **alta** |
| S7 | **Driver do LED IR da câmara** (`qcom,camera-ir-led`) + o filtro IR-cut | pequeno | média |
| S8 | **Driver IR por SPI** (`ir-spi-led`) + nó de DT | pequeno | **baixa** — confirmar primeiro se a peça existe |
| S9 | **Stack de rádio FM** (transporte `radio_iris_transport`, HCI, patches via QMI, calibração por I²C) | **grande** | baixa |

> **S4 é a próxima acção de maior rendimento.** O ficheiro
> `rea/02-notes/audio-mixer-paths.md` tem o quadro completo: são 607 rotas, e o
> mapa de microfones está lá. O que falta é transcrever o *routing table* do
> vendor para o driver mainline do WCD9375. É trabalho de meio dia, não de
> semanas.

---

## Parte 2 — Compilar e criar a versão final

Este é o caminho completo, do repositório limpo até uma imagem flashável.
Os tempos são de um host x86_64 com 8 núcleos e 16 GB.

### 2.1 Pré-requisitos

```sh
# no host (Debian/Ubuntu)
sudo apt install git python3 python3-pip bc flex bison cpio rsync \
                 make gcc clang lld llvm \
                 e2fsprogs dosfstools device-tree-compiler \
                 zstd openssl \
                 kpartx parted sgdisk fuse3 \
                 qemu-user-static arch-test
```

> **Dependências verificadas em falta nesta máquina** (2026-10-20):
> `bc` (o kernel falha sem ele), `kpartx` (o `pmbootstrap` recusa-se a arrancar
> sem ele), `sgdisk`, `fuse3`, `qemu-user-static` e `arch-test`.
>
> `clang` e `lld` são **obrigatórios**: o `APKBUILD` tem `pmb:cross-native` e
> a receita compila com LLVM.

```sh
# pmbootstrap, a partir da cópia local
cd /home/manutencao/Documents/pocox3-nfc/postmarketos/pmbootstrap
python3 -m venv .venv && . .venv/bin/activate
pip install -e .
# ou, mais simples, usar sempre: python3 pmbootstrap.py <comando>
```

> Verificar que ficou tudo:
>
> ```sh
> cd /home/manutencao/Documents/pocox3-nfc/postmarketos/pmbootstrap
> python3 pmbootstrap.py doctor
> ```

### 2.2 Descarregar as fontes de upstream

```sh
cd /home/manutencao/Documents/pocox3-nfc/postmarketos
./fetch-upstream.sh
```

Isto clona três coisas para `postmarketos/upstream/`:

| Repositório | URL | Porque |
|---|---|---|
| `pmaports` | `gitlab.postmarketos.org/postmarketOS/pmaports.git` | as receitas de pacotes |
| `sm7150-mainline/postmarketos` | `github.com/sm7150-mainline/postmarketos.git` | o pacote do dispositivo e do kernel SM7150 |
| `woodyst/surya-pmos` | `github.com/woodyst/surya-pmos.git` | a origem dos patches |

> ⚠️ **O `pmaports` está no GitLab, não no GitHub.** Uma tentativa anterior
> falhou por isso.

### 2.3 Escolher o perfil e o painel

O POCO X3 NFC tem **dois painéis**, Huaxing e Tianma, e cada um precisa do seu
u-boot e do seu device tree. Descobrir o painel certo é o primeiro teste real:

```sh
# se já há Android no telefone:
adb shell getprop ro.build.version.incremental
# ou, pelas fingerprints do DT:
strings /proc/device-tree/model
```

Se o ecrã ficar preto depois de instalar, **não é brick**: é o painel
errado. Trocar o u-boot resolve.

### 2.4 Construir a imagem

Este `pmbootstrap` (3.12.1) configura-se por `pmbootstrap config <chave>
<valor>`, e o `init` não aceita opções de linha de comando. A sequência é:

```sh
cd /home/manutencao/Documents/pocox3-nfc
PMB="sudo python3 postmarketos/pmbootstrap/pmbootstrap.py"

# 1. dizer ao pmbootstrap o que construir e onde
$PMB config device qcom-sm7150
$PMB config ui postmarketos-ui-plasma-mobile
$PMB config kernel postmarketos-qcom-sm7150
$PMB config work "$PWD/build-pmb"
$PMB config aports "$PWD/postmarketos/upstream/pmaports"
$PMB config build_default_device_arch False

# 2. preparar o chroot
$PMB init
```

> 📌 **`work` e `aports` têm de ser absolutos.** O `pmbootstrap` guarda-os
> na configuração e usa-os em todos os comandos seguintes; um caminho
> relativo quebra a meio.
>
> 📌 **`build_default_device_arch False`** — este `pmbootstrap` compila o
> pacote do dispositivo para a arquitectura do host por omissão, o que está
> errado para um `arm64`. Verificar com `$PMB config device` antes de
> continuar.

Depois, copiar os overlays. O caminho dos aports sai da configuração:

```sh
PMAPORTS=$(python3 postmarketos/pmbootstrap/pmbootstrap.py config aports)

# 2. kernel: 140 patches, a receita e a config
cp surya-pmos/kernel/*.patch surya-pmos/kernel/APKBUILD \
   surya-pmos/kernel/config-* \
   "$PMAPORTS/device/testing/linux-postmarketos-qcom-sm7150/"

# 3. libcamera com autofocus. Manter os patches 0001-0003 do postmarketOS;
#    os nossos são 0004 e 0005, e o APKBUILD lista todos.
cp surya-pmos/packages/libcamera/*.patch surya-pmos/packages/libcamera/APKBUILD \
   "$PMAPORTS/temp/libcamera/"

# 4. libqmi com as mensagens das constelações GNSS. Opcional: tudo o resto
#    funciona sem isto. O libqmi não está no pmaports, por isso compila-se
#    a partir de temp/.
mkdir -p "$PMAPORTS/temp/libqmi"
cp surya-pmos/packages/libqmi/*.patch surya-pmos/packages/libqmi/APKBUILD \
   "$PMAPORTS/temp/libqmi/"

# 5. hexagonrpcd que serve o PD de áudio do ADSP (cancelamento de eco) e
#    que escreve o registo de sensores. Também a partir de temp/.
mkdir -p "$PMAPORTS/temp/hexagonrpcd"
cp surya-pmos/packages/hexagonrpcd/* "$PMAPORTS/temp/hexagonrpcd/"

# 6. checksums e build
$PMB checksum linux-postmarketos-qcom-sm7150 libcamera libqmi hexagonrpcd
$PMB shutdown          # <- ver os avisos abaixo
$PMB install
```

#### ⚠️ Os dois avisos que custam uma noite

1. **`pmbootstrap checksum` deixa o chroot montado.** O build seguinte falha
   com *"Failed to umount … /mnt/pmbootstrap/packages"*. Correr
   `pmbootstrap shutdown` entre os dois.

2. **Um pacote que não reconstrói.** O pmbootstrap diz "up to date" e salta-o.
   Incrementar o `pkgrel` no `APKBUILD` correspondente.

#### Onde fica a imagem

```sh
find build-pmb -name '*.img' | head
# tipicamente:
#   build-pmb/images/rootfs.img
#   build-pmb/images/boot.img
```

#### Se a imagem não construir

```sh
$PMB log > build.log 2>&1      # o log completo
$PMB status                    # o estado de cada etapa
$PMB zap                       # limpar e recomeçar
```

### 2.5 Build só do kernel (ciclo rápido)

Para iterar sobre patches sem refazer a imagem inteira — o `deploy.es.md`
§1 já documenta isto, e a parte que mais importa:

```sh
export PATH=/ext_r/ext_edi/src/suria/llvm-shim:$PATH
make LLVM=1 ARCH=arm64 LOCALVERSION= -j8 vmlinuz.efi modules
make LLVM=1 ARCH=arm64 LOCALVERSION= INSTALL_MOD_STRIP=1 \
     INSTALL_MOD_PATH=<staging> modules_install
```

> 📌 **`LOCALVERSION=` no ambiente é obrigatório.** O `setlocalversion` acrescenta
> um `+` se a variável não estiver definida, e então o directório dos módulos
> não corresponde — que é exactamente o caso da compilação misturada. Um
> `.scmversion` vazio **não** chega.
>
> 📌 **Kernel e módulos têm de ser da mesma compilação.** Instalar um
> `vmlinuz` novo com os módulos velhos dá um telefone que **arranca, chega ao
> `greetd` e morre em silêncio aos ~25 s**, sem Oops e sem nada no `ramoops`:
> `CONFIG_MODVERSIONS` está desligado e nada detecta o desajuste.
>
> 📌 `INSTALL_MOD_STRIP=1` deixa os módulos em ~20 MB em vez de 241 MB.

### 2.6 Gravar no telefone

Ver o `README.md` §"Flashing it onto the phone" para o procedimento completo
(u-boot, vbmeta vazio, `fastboot erase dtbo`). O essencial:

```sh
fastboot flash boot u-boot-sm7150-xiaomi-surya-huaxing.img
fastboot erase dtbo
fastboot flash vbmeta        vbmeta.img        --disable-verity --disable-verification
fastboot flash vbmeta_system vbmeta_system.img --disable-verity --disable-verification
$PMB flasher flash_rootfs
fastboot reboot
```

> ⚠️ O `dtbo` do factory **tem de ser apagado** ou briga com o do mainline.
>
> ⚠️ **Este telefone nunca se desliga de verdade**: o u-boot reinicia-o, mesmo
> a partir do seu próprio menu. Não ler um reinício como falha de desligar.

### 2.7 Instalar a configuração do dispositivo

```sh
cd surya-pmos
./scripts/install-on-device.sh <hostname-ou-ip>
```

O script só escreve configuração; nunca toca no kernel nem nos pacotes, que
vêm da imagem. Ele recusa-se a correr com um kernel anterior a `r93`, porque
o `VoiceCall.conf` usa controlos que só existem a partir daí.

> 📌 **A ordem de carga está invertida** em relação ao que se esperava: o
> codec de áudio tem de vir **antes** do Bluetooth, senão o adaptador fica
> `DOWN RAW`. Ver o `deploy.es.md` §8.
>
> 📌 **Os ficheiros lua do wireplumber vão para `~/.local/share/…`, não
> `~/.config/…`.** Mal colocados, o wireplumber não arranca e o telefone fica
> **sem áudio nenhum**.

---

## Parte 3 — Testes reais: o que correr e o que medir

### 3.1 Antes de mais nada: uma segunda partição

**Não testar a receita no telefone que funciona.** A receita nunca foi
executada de ponta a ponta e vai falhar em algum lugar. Usar um cartão SD ou
uma segunda partição, ou um segundo telefone.

### 3.2 A receita de deploy, passo a passo

O `docs/deploy.es.md` tem a receita completa, em 12 secções, com as correcções
documentadas. Executá-la por ordem, e **anotar cada ponto em que foi
necessário intervir à mão** — essa lista é o produto real deste exercício.

> ⚠️ **Os guiões `10-paquetes` … `70-bluetooth-llamadas` de que o
> `pending.es.md` fala não estão neste repositório.** Foram guiões da sessão
> de desenvolvimento. O que existe é o `install-on-device.sh`, que instala
> a configuração de uma vez, e o `deploy.es.md`, que descreve a receita por
> secções. **Reconstruir os guiões numerados é a primeira tarefa da Fase B**,
> porque sem eles não há forma de repetir a receita passo a passo.

### 3.3 A bateria de medições

O critério de aceitação não é "não crasha". É medido.

| # | O que | Como | Critério |
|---|---|---|---|
| T1 | Estéreo L/R | `caza-loteria.sh N`, com o micro do telefone | cada canal toca o seu lado |
| T2 | Auricular do telefone | `verify-call-routing.sh` | o som sai pelo auricular |
| T3 | Chamada, áudio nos dois sentidos | chamada real | "o que falo" chega ao outro |
| T4 | Volume da chamada, por destino | por auricular, altifalante, auscultadores | o volume é independente por destino |
| T5 | Mover a chamada para o altifalante a meio | chamada em curso | a comutação funciona |
| T6 | **Mover a chamada de volta para o auscultadores** | chamada em curso | ⚠️ **sabe-se que falha** — ver §4.1 |
| T7 | Chamada com auscultadores BT | `btmon` + `hcitool con` | `SCO Data TX` = 0 (offload real) |
| T8 | Aurora cancelada | medir o eco | ~23 dB de redução; **precisa da calibração de fábrica** |
| T9 | Câmara traseira | `pipewire` + `gst-launch` | foco automático a funcionar |
| T10 | Câmara frontal | idem | ⚠️ **sabe-se que não há fluxo** — ver §4.2 |
| T11 | Suspensão | `cat /sys/power/mem_sleep` | idle draw baixo, o telefone dorme |
| T12 | Bateria | `/sys/class/power_supply/battery/capacity` | 19 pontos de erro nos 19% corrigidos |
| T13 | GNSS | `gnssctl` / a aplicação de mapas | Galileo e BeiDou visíveis |
| T14 | Notificações | tocar o telefone | som **e** vibração |
| T15 | USB OTG | teclado USB | escreve no terminal |
| T16 | Arranque a frio | desligar, arrancar | arranca em <30 s, sem triangular kernels |
| T17 | Estabilidade (48 h) | deixar a correr | sem reinício, sem freeze de UFS |

> ⚠️ **`caza-loteria.sh`, `verify-call-routing.sh` e `estado/verificar.sh` não
> estão neste repositório.** O `deploy.es.md` §10 cita-os, mas são guiões da
> sessão de desenvolvimento que nunca foram commitados. **Escrever cada um
> deles é parte da Fase C** — sem eles, os testes T1, T2 e T17 não têm
> critério objectivo.
>
> 📌 A regra do `caza-loteria.sh`: tons de amplitude ≤30 % e ≤20 s, nunca
> secções longas em loop.

> ⚠️ **T8 precisa da calibração de voz de fábrica**, que é da Xiaomi e não é
> redistribuída. Sem ela, a chamada funciona mas o eco não é cancelado. O
> `docs/echo-cancellation.es.md` tem o procedimento exacto.

### 3.4 O que fazer quando um teste falha

1. **Não reiniciar de imediato.** O `pstore` guarda o rasto:
   `/sys/fs/pstore/`. Um reinício apaga o `dmesg`.
2. Correr `dmesg | grep -iE 'oops|warn|BUG|panic'`.
3. Guardar o estado: `dmesg`, `journalctl -b -1`, `cat /sys/fs/pstore/*`.
4. Se foi um freeze, `/dev/mem` está livre e o `mmr.c` de
   `rea/04-tools/` lê os registos directamente. Ler **durante** a captura — com
   o relógio parado dá zero ou bloqueia.
5. Para o áudio, `~/capturar-llamada.sh` no telefone escreve em
   `~/capturas/` (sobrevive a reinícios), com `btmon`, amostragem do
   `hcitool con` de 0,5 em 0,5 s, `dmesg` e registos de utilizador.

---

## Parte 4 — Os bloqueadores conhecidos

### 4.1 A volta ao auscultadores a meio da chamada fica muda

**Estado**: auscultadores OK → altifalante OK → auscultadores mudos.
Sobrevive a eliminar o bombeio por HCI, portanto é **independente do
offload**. Refutado com medição: não é o vocproc, nem as rotas, nem os canais
do bus, nem o SCO antigo nem o fresco.

**Mitigação actual**: com auscultadores, não mudar de saída a meio da
chamada. Para passar ao altifalante, desligar e ligar de novo.

**Hipóteses a testar, por ordem**:

1. O `q6routing` precisa de um sinal explícito de que a saída mudou, e
   com auscultadores BT o `device` que o `q6voice` abre é diferente. Ver
   `docs/bt-return-to-headset.es.md`.
2. O patch 0130 remove os canais do SLIMbus, mas talvez com o auscultador
   BT a sequência precise de um segundo `remove_channels` depois do
   comutador, e não antes.
3. Comparar os registos do DSP com auscultadores Wired vs. BT no momento da
   comutação. O `q6voice` tem `q6voice_device` fixo em 4.

### 4.2 A câmara frontal não tem fluxo

O S5K3T2 transmite em **C-PHY** e o receptor está em **D-PHY**. Todas as
hipóteses foram fechadas com medições: não é o número de lanes, nem a
atribuição, nem a polaridade do mux, nem o I²C (que falha
intermitentemente — e quando o probe falha, o `libcamera` não vê *nenhuma*
câmara, nem a traseira).

**O que falta**: um driver que configure o receptor para C-PHY. O
`camss`/`csiphy` do mainline tem C-PHY para o MSM, mas não para o SM7150.

**Estado do sensor frontal**: o `sensormodule` do S5K3T2 está em
`rea/00-inputs/`, decodificado: 66 passos de power-up, 292 942 escritas de
registo. O mapa está em `rea/02-notes/camera-sensormodule.md`.

### 4.3 A série de patches tem contadores incoerentes — **bug do repositório**

Os 140 patches estão numerados `0001`–`0140`, mas o campo `Subject:` de 30
deles perdeu o contador (`[PATCH]` em vez de `[PATCH N/M]`), e os
denominadores são `/106` (patches 1–106), `/113` (112–113) e `/2` (116–117).

**Consequência**: `git am` falha, porque os índices não formam uma série
contínua.

**Correção**: renormalizar a série a partir do `git log` do repositório de
origem, como o `docs/deploy.es.md` §1 já fazia para os 106 patches
originais.

```sh
# reescrever os Subject: para [PATCH N/140], de 0001 a 0140
cd surya-pmos/kernel
for f in *.patch; do
  n=${f%%-*}
  i=$((10#$n))
  sed -i "s|^Subject: \[PATCH[^]]*\]|Subject: [PATCH $i/140]|" "$f"
done
```

> 📌 **Não usar `seq -w`**: com `seq -w 1 140` os números saem de 1 a 140 em
> vez de `001` a `140`, e o `ls ${i}-*.patch` não encontra nada. O `for f in
> *.patch` com `${f%%-*}` evita o problema — o número sai do próprio nome do
> ficheiro, que já está certo.
>
> 📌 O `Subject:` pode ocupar **duas linhas** (a continuação indentada faz
> parte do assunto). O `sed` só toca na primeira, que é a que tem o
> contador — o resto fica intacto.

> ⚠️ Isto é **cosmético** para o `APKBUILD` (que só se importa do nome do
> ficheiro) mas **essencial** para aplicar a série com `git am`. O
> `APKBUILD` lista correctamente os 140 ficheiros, e o `pmbootstrap` aplica-os
> pela lista, não pelo `Subject:` — por isso o build do pmbootstrap funciona
> mesmo com os contadores errados. O que falha é o fluxo de trabalho com
> `git am`.

### 4.4 O ACDB e a calibração de voz

O cancelamento de eco precisa da **calibração de voz de fábrica**, que é da
Xiaomi. Não é redistribuída e não pode ser sintetizada.

O que *é* possível fazer:

1. Documentar exactamente que ficheiro do ACDB a contém, e em que tabela.
   O formato do ACDB está descrito no `libacdbloader.so`.
2. Verificar se a calibração pode ser **extraída do próprio telefone** — o
   `vendor` do Android está lá, em `/vendor/etc/acdbdata/`. É o mesmo
   percurso que o `docs/blobs.md` descreve para o resto.
3. Escrever o script de extracção, para quem tiver o telefone.

### 4.5 O `mixer_paths` — qual dos quatro é o deste board

O HAL `audio.primary.sm6150.so` escolhe em runtime. As quatro afinações
diferem mais do que em valores (ver `rea/02-notes/audio-mixer-paths.md`):

| Ficheiro | Amplificador |
|---|---|
| `mixer_paths_wcd9375.xml` | TAS2562 |
| `mixer_paths_idp.xml` | TAS2562 |
| `mixer_paths_qrd.xml` | WSA — **este board não tem** |
| `mixer_paths_tavil.xml` | nenhum |

Determinar qual é usado:

```sh
# no telefone, em runtime
adb shell getprop | grep -iE 'audio|mixer|platform'
# e o log do HAL na inicialização
adb logcat -b all | grep -iE 'mixer_paths|audio_platform'
```

### 4.6 A IR de controlo remoto pode não existir

O HAL de IR do Android conduz `/dev/spidev0.1`, mas:

- o nó da **SPI0 está `disabled`** no DTBO e não tem dispositivo filho;
- **não há `ir-spi-led`** (nem `led-active-low`, nem `duty-cycle`) em lado
  nenhum do DTBO;
- **o kernel de fábrica não tem driver de IR** — nenhum dos 38 módulos do
  vendor, e nada no `kernel.uncompressed`.

A IR que **existe** é a da câmara: o LED IR e o filtro IR-cut, nos GPIO 73 e
74, com o driver `qcom,camera-ir-led` que o mainline não tem.

**Confirmar fisicamente antes de escrever o driver.** Se a peça existir, o
mainline já tem `CONFIG_IR_SPI=m` e o driver `ir-spi-led` genérico; o que
falta é o nó de DT e possivelmente um regulador.

Ver [`rea/02-notes/ir-and-fm.md`](../../rea/02-notes/ir-and-fm.md).

### 4.7 O rádio FM é o WCN3990, não um chip à parte

A HAL de FM (`vendor.qti.hardware.fm@1.0-impl.so`) fala com o Bluetooth
(`HIDL_FETCH_IFmHci`) — o FM viaja por HCI até ao WCN3990 ("cherokee", o
mesmo chip do Bluetooth e do Wi-Fi).

O boot precisa de:
1. `echo 1 > /sys/module/radio_iris_transport/parameters/fmsmd_set`;
2. `fm_qsoc_patches`, que descarrega os patches **via QMI** (do modem) e
   escreve a calibração do DAC **por I²C** (notch filters e spur table).

Isto é um trabalho grande, e a parte difícil não é o driver: é o download
dos patches e da calibração, que precisa do modem e do codec envolvidos no
arranque, na ordem certa, com o tipo de chip certo.

---

## Parte 5 — Ordem de trabalho sugerida

Cada passo é pequeno, verificável e deixa o telefone a funcionar.

### Fase A — Desbloquear o build (sem tocar no telefone)

| # | Tarefa | Entrega |
|---|---|---|
| A1 | `fetch-upstream.sh` com o `pmaports` do GitLab | `upstream/` preenchido |
| A2 | `sudo apt install bc` e as restantes dependências | host pronto |
| A3 | Renormalizar os Subject: dos 140 patches (§4.3) | série aplicável com `git am` |
| A4 | `pmbootstrap init` + `checksum` + `install` numa imagem de stock | **imagem constrói** |
| A5 | Compilar o kernel isoladamente (§2.5) e comparar com o implantado | `vmlinuz.efi` idêntico |

> **A5 é o marco.** Se o kernel compilado daqui for bit a bit igual ao que
> está implantado no telefone, a receita está correcta e o resto é testar.

### Fase B — A receita de deploy, de ponta a ponta

| # | Tarefa | Entrega |
|---|---|---|
| B1 | Instalar a imagem numa **segunda partição** | telefone a funcionar |
| B2 | Correr o `deploy.es.md` de 10 a 70 | **lista de onde foi preciso intervir** |
| B3 | Transformar essa lista em correcções ao `deploy.es.md` | receita corrigida |
| B4 | Repetir numa instalação limpa | **reproduzível** |

> **B4 é o que o `pending.es.md` chama de "PENDIENTE MAYOR"** e o que
> transforma "verificado no kernel e descrito no resto" em "reproduzível".

### Fase C — Testes por subsistema

| # | Tarefa | Entrega |
|---|---|---|
| C1 | A bateria de medições T1–T17 | tabela de resultados |
| C2 | O routing table dos microfones, transcrito do `mixer_paths` | patch do WCD9375 |
| C3 | A comutação de auscultadores a meio da chamada (§4.1) | ou arrumado, ou documentado |
| C4 | A câmara frontal: C-PHY no receptor | patch do `csiphy` |

### Fase D — O que falta escrever

| # | Tarefa | Esforço |
|---|---|---|
| D1 | Driver NFC (PN557) — o formato do firmware já está decodificado | grande |
| D2 | Handshake de carregamento rápido — precisa do `usbpd` do mainline | médio |
| D3 | A-GPS no modem | médio |

---

## Apêndice A — Comandos de diagnóstico

Estão em `rea/04-tools/`, todos só-leitura excepto indication em contrário:

```sh
# câmara
rea/04-tools/camera_inventory.py <dir>       # o inventário dos 12 blobs
rea/04-tools/parse_sensormodule.py <blob>    # o formato do blob
rea/04-tools/mmr.c                           # MMIO por /dev/mem
rea/04-tools/csiphy-lane-decode.sh <base>    # o estado por carril
rea/04-tools/csiphy_latch.sh <base> <bus> <addr>   # com e sem sinal
rea/04-tools/diagnostico_camara.sh           # um retrato de todo o stack

# NFC
rea/04-tools/extract_pn557_fw.py <lib>      # a sequência de firmware
rea/04-tools/parse_nxp_rf.py <conf>          # os blocos de calibração

# áudio
rea/04-tools/parse_mixer_paths.py <xml>      # as rotas
rea/04-tools/audio_inventory.py <dir>        # o inventário

# GNSS
rea/04-tools/gnss_config.py <dir>            # a configuração

# carga
rea/04-tools/parse_sensormodule.py ...       # (ver as notas da carga)
rea/04-tools/resolve_plt.py <elf>            # resolver os stubs do PLT
rea/04-tools/disasm.py <elf> --range <a> <b> # desassemblagem simples
```

## Apêndice B — Onde está cada coisa

| Onde | O quê |
|---|---|
| `surya-pmos/README.md` | o que funciona, em inglês |
| `surya-pmos/docs/*.es.md` | o registo de trabalho, em espanhol |
| `surya-pmos/docs/deploy.es.md` | a receita de implantação, em espanhol |
| `surya-pmos/docs/pending.es.md` | a lista de pendentes, em espanhol |
| `surya-pmos/kernel/` | os 140 patches, o APKBUILD e a config |
| `surya-pmos/device/` | a configuração que vai para o telefone |
| `surya-pmos/scripts/` | `install-on-device.sh`, `setup-vendor-mount.sh` |
| `rea/02-notes/` | **as análises novas**: carga, câmara, NFC, áudio, GNSS |
| `rea/04-tools/` | **as ferramentas novas** |
| `rea/03-c-reimplementation/` | a reimplementação em C do handshake de carga |
| `postmarketos/` | o `pmbootstrap`, a imagem pré-compilada, o `fetch-upstream.sh` |

## Apêndice C — Licenças

O que se publica e o que não:

| Publicado | Não publicado |
|---|---|
| as análises, as ferramentas, a reimplementação | os binários do vendor (`rea/00-inputs/{audio,gnss,nfc}`) |
| os factos de interface extraídos (chaves HMAC, tabelas QMI) | o ACDB de fábrica (calibração por dispositivo) |
| os `mixer_paths_*.xml` e as configs (Apache-2.0 da AOSP) | o firmware extraído do factory OTA |
| a sequência de firmware do PN557, decodificada | a calibração RF como constante pública |

Os factos de interface extraídos de um build MIUI publicamente distribuível
são publicados como o repositório já faz com as tabelas QMI LOC
(`surya-pmos/tools/qmi-loc-idl/`).
