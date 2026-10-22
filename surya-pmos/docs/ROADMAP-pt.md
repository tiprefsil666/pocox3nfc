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

## Parte 0 — O que já está feito por outros

> ⚠️ **Ler esta parte antes de começar a escrever código.** O projecto
> `sm7150-mainline` já porta este mesmo SoC para o postmarketOS, e há
>bloqueadores que estão resolvidos lá. A análise completa, com as
> fontes, está em
> [`rea/02-notes/upstream-parallel-work.md`](../../rea/02-notes/upstream-parallel-work.md).

O que a comunidade já testou:

| | |
|---|---|
| **A instalação oficial** | [`wiki.nura.eco/wiki/Qualcomm_SM7150_(qcom-sm7150)`](https://wiki.nura.eco/wiki/Qualcomm_SM7150_(qcom-sm7150)) — o pacote de dispositivo é o **genérico `qcom-sm7150`**, o U-Boot é *chainloaded* pelo bootloader de fábrica, e a raiz vai para `userdata` |
| **O estado das funções** | a wiki do [surya](https://wiki.nura.eco/wiki/Xiaomi_POCO_X3_NFC_(xiaomi-surya)) tem a tabela testada: câmara **quebrada**, **IR TX quebrado**, **GPS quebrado**, áudio **parcial**, bateria **parcial**, e everything else a funcionar |
| **A configuração de áudio** | o pacote `alsa-ucm-conf-qcom-sm7150`, do mesmo projecto — ⚠️ **colide com a nossa** (§4.5) |
| **A árvore de dispositivo da fábrica** | publicada em `sm7150-mainline/downstream-fdt` — é a **contra-prova** das notas de análise |
| **Imagens semanais** | `sm7150-mainline/nightly-builds` — uma imagem por semana, para cada dispositivo |
| **Um port NixOS** | `codeberg.org/ungeskriptet/nixos-qcom`, com **um dispositivo por painel** |
| **Os nossos próprios patches de foco** | estão a ser **aceites no upstream do libcamera** (§4.8) |

Duas conclusões que mudam o plano:

1. **A câmara, a IR e o GPS estão broken no port oficial também.** O que
   este port tem de fazer é melhorá-los, não tê-los de primeira. O port
   oficial é a **referência para o que funciona** — ecrã, toque, modem,
   NFC, sensores, bootloader.
2. **Os dois "N" que faltam na tabela de componentes e que o mainline já
   tem driver** são exactamente os dois com que este port se tem
   debatido: os **microfones WCD9375** e o **áudio USB-C FSA4480**. São
   trabalho de **device tree**, não de driver — o que muda completamente a
   sua dimensão.

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

A coluna da direita é o estado **testado pela comunidade** — a wiki do
projecto upstream. Serve de referência: onde diz "broken" lá, também está
por fazer aqui, e a prioridade é a mesma.

| # | Item | Como testar | Critério de aceitação | Upstream |
|---|---|---|---|---|
| H1 | **Carga rápida de 33 W** | carregador Xiaomi + `batterysecret` de produção | o `usbpd` marca `USB_HVDCP_3` e o `bq2597x` mostra o limite elevado | `N` |
| H2 | **NFC** | encostar uma etiqueta | o `nfc` do mainline lê a etiqueta; hoje **não há driver** | ✅ Works |
| H3 | **Câmara frontal** (S5K3T2) | `pipewire` + `gst-launch` | sem pacotes, sem erro; hoje não há fluxo | ❌ Broken |
| H4 | **Câmara de profundidade** (GC02M1B, OV02B1B) | idem | idem | ❌ Broken |
| H5 | **A-GPS** | frio, ao ar livre | fix em <30 s; hoje o fix frio é lento | ❌ Broken |
| H6 | **USB OTG** com teclado | ligar um teclado USB | o teclado escreve no terminal | ✅ Works |
| H7 | **Auriculares por cabo** (USB-C) | ligar auscultadores | audio bidireccional | ❌ `N` |
| H8 | **Slot SIM 2** | inserir um segundo SIM | o modem detecta-a | ⚠️ quirky |
| H9 | **TV-out** (via USB-C) | ligar um ecrã | não testado em lado nenhum | — |
| H10 | **IR de controlo remoto** | ver [`rea/02-notes/ir-and-fm.md`](../../rea/02-notes/ir-and-fm.md) | ⚠️ **o firmware sugere que não existe** — confirmar fisicamente antes de escrever código | ❌ Broken |
| H11 | **IR da câmara + filtro IR-cut** | abrir a câmara no escuro | o filtro muda de estado, a câmara vê em IR | — |
| H12 | **Rádio FM** | ligar auscultadores, abrir a app de rádio | ⚠️ **todo o stack falta no mainline** | — |

> 📌 **H7 (os auscultadores por cabo) é mais fácil do que parece.** O
> FSA4480 — o controlador de áudio analógico do USB-C — está no mainline
> (`drivers/usb/typec/mux/fsa4480.c`) e o device tree do factory tem o
> `fsa4480-i2c-handle`. O que falta é a **device tree**, não um driver.
> O mesmo vale para os **microfones WCD9375** (`wcd937x.c` no mainline).
>
> A tabela de componentes da wiki marca estes dois como `N` — e a nota
> «supported in this driver» aponta para o driver do mainline. São
> **as duas maiores oportunidades** que restam, e as mais baratas.

> 📌 **H8: há uma peculiaridade conhecida.** A wiki avisa: *"Actually there is
> an error unlocking SIM-Card on Slot1. If you get an (3)Internal error
> AND you are already on edge (tqftpserv >= 1.2) you could try the
> SD-Card/SIM-shared slot."* Se o teste do slot 2 falhar, **isto é
> esperado** e não é um bug do port.

### 1.3 Software que falta escrever

| # | Falta | Esforço | Prioridade |
|---|---|---|---|
| S1 | **Driver NFC** (PN557) | grande | baixa — a NFC é um extra |
| S2 | **Handshake de carregamento rápido** | médio | **média** — precisa do `usbpd` do mainline |
| S3 | **Driver do amplificador TAS2562** | já existe (patches 0013–0016, 0022–0027) | — |
| S4 | **Roteamento de microfones** do WCD9375 — ⚠️ **o codec já está ligado** (patch 0031); falta transcrever o *routing table* | pequeno | **alta** — está no `mixer_paths` |
| S5 | **A-GPS no modem** | médio | média |
| S6 | **Portar o `mixer_paths` para mainline** | pequeno | **alta** |
| S7 | **Driver do LED IR da câmara** (`qcom,camera-ir-led`) + o filtro IR-cut | pequeno | média |
| S8 | **Driver IR por SPI** (`ir-spi-led`) + nó de DT | pequeno | **baixa** — confirmar primeiro se a peça existe |
| S9 | **Stack de rádio FM** (transporte `radio_iris_transport`, HCI, patches via QMI, calibração por I²C) | **grande** | baixa |
| **S10** | **Áudio USB-C (FSA4480)** — o driver do mainline já existe e a config já o activa; falta a **device tree** | pequeno | **alta** — a receita está em [`rea/02-notes/usb-c-audio-fsa4480.md`](../../rea/02-notes/usb-c-audio-fsa4480.md) |
| **S11** | **Conciliar o `alsa-ucm-conf` oficial** com a nossa configuração de áudio | pequeno | **alta** — ver §4.5.1 |
| **S12** | **Migrar os patches de foco do libcamera** para o upstream | médio | média — ver §4.8 |

> **S4 é a próxima acção de maior rendimento.** O ficheiro
> `rea/02-notes/audio-mixer-paths.md` tem o quadro completo: são 607 rotas, e o
> mapa de microfones está lá. O que falta é transcrever o *routing table* do
> vendor para o driver mainline do WCD9375. É trabalho de meio dia, não de
> semanas.
>
> 📌 **E é agora a segunda acção de maior rendimento, depois de S11.**
> O **FSA4480** (áudio analógico do USB-C) tem o driver no mainline
> (`drivers/usb/typec/mux/fsa4480.c`), a config do nosso kernel já o
> activa (`CONFIG_TYPEC_MUX_FSA4480=y`), o bus I²C onde ele vive
> (`i2c9`, o QUPv3 SE9) **já está ligado** pelo patch 0042, e a device
> tree da fábrica dá tudo o resto: o endereço `0x43`, o pino do *enable*
> (GPIO 42) e a sua configuração.
>
> **Falta só a device tree**, e a receita está escrita, passo a passo, em
> [`rea/02-notes/usb-c-audio-fsa4480.md`](../../rea/02-notes/usb-c-audio-fsa4480.md).
> A referência é a `sm8350-hdk` do mainline.
>
> 📌 **A comparação completa está feita.** A árvore de dispositivo da
> fábrica contra a que os 140 patches produzem está em
> [`rea/02-notes/port-vs-factory.md`](../../rea/02-notes/port-vs-factory.md),
> e os 140 patches aplicam-se limpos sobre a base fixada
> (`v7.1_rc3` @ `1fd06fd1`) — verificado por
> `build/15-verify-series.sh`.
>
> As quatro lacunas que ficam: o **FSA4480** (áudio USB-C, a receita
> está escrita), a **NFC**, o **leitor de impressão digital** e o **LED
> IR da câmara**.
>
> ⚠️ **E um perigo que não é uma lacuna:** a tabela OCV da bateria é uma
> **calibração por dispositivo** que está num patch partilhado. O patch
> 0117 remove a tabela upstream com este aviso — *"Left in place it is
> worse than nothing, because it reports a calibrated-looking percentage
> that is wrong for the new cell"* — e o 0126 volta a pôr uma tabela
> medida na bateria de substituição. Quem compilar este kernel com uma
> célula diferente fica com uma percentagem errada e com ar de
> calibrada. A tabela é **dados, não um patch**, e quer viver num sítio
> que diga de quem é a bateria.
>
> 📌 **O WCD9375 já está ligado** — o patch 0031 põe os macros do LPASS,
> os controladores SoundWire, o codec e o *DAI link* de captura, e o
> patch 0034 e 0035 tratam do SoundWire e do pino de reset. O que falta
> em S4 é a parte de **transcrever o *routing table* do vendor** para os
> controlos do driver do mainline — não é ligar o codec, que já está
> ligado.
>
> Isto é o que distingue o estado deste port do oficial: a wiki classifica
> os dois componentes como `N`, e aqui o WCD9375 **já funciona**.
>
> 📌 **S1 (a NFC) mudou de prioridade — e de tamanho.** A wiki classifica
> a NFC como **Works** no port oficial, e o device tree confirma o NXP NCI
> (`compatible = "qcom,nq-nci"`). O driver do mainline existe
> (`drivers/nfc/nxp-nci`), e o **Nothing Phone (1)** — o mesmo SM7325, com
> o mesmo bus QUPv3 SE2 e o mesmo endereço `0x28` — **já o faz no
> mainline**.
>
> Deixa de ser um "grande" (escrever um driver) e passa a ser um
> "pequeno" (ligar um nó): o bus `i2c2` está `disabled` no mainline, e o
> nó é `nfc@28` com um `compatible` diferente e três GPIOs (o *enable*, o
> *clock request* e o *interrupt*).
>
> A receita completa está em
> [`rea/02-notes/nfc-wiring.md`](../../rea/02-notes/nfc-wiring.md). A
> única coisa que não se sabe sem o aparelho é **qual dos GPIO 12 e 36 é
> o *enable*** — a árvore de fábrica agrupa-os e não diz.

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

> 📌 **O procedimento oficial, testado pela comunidade**, está na
> [wiki.nura.eco](https://wiki.nura.eco/wiki/Qualcomm_SM7150_(qcom-sm7150))
> e é mais curto do que o que estava aqui. O `build/40-flash.sh` já o
> segue.

```sh
# o u-boot do painel certo deste telefone
fastboot erase dtbo
fastboot flash boot u-boot-sm7150-xiaomi-surya-<painel>.img

# e a raiz
$PMB flasher flash_rootfs
```

Três coisas que a wiki oficial diz e que não são óbvias:

- **O pacote de dispositivo é o genérico `qcom-sm7150`**, não
  `device-xiaomi-surya`. Os pacotes por dispositivo foram removidos em
  Março de 2025, porque o U-Boot passa a escolher a device tree sozinho.
- **O U-Boot é *chainloaded* pelo bootloader de fábrica.** O bootloader
  primário não é substituído: o U-Boot vai para a partição `boot` e a
  Xiaomi arranca-o. (O bootloader continua a ter de estar desbloqueado.)
- **A raiz vai para `userdata`**, e o **esquema de partições mudou
  completamente** com a passagem para o U-Boot. O esquema antigo e o novo
  são incompatíveis e **não há migração** — é uma instalação limpa ou
  nada. Ver a
  [nota de migração](https://postmarketos.org/edge/2025/03/09/sm7150-generic-migration/).

E o `vbmeta` vazio, que o `README.md` antigo pedia:

```sh
fastboot flash vbmeta        vbmeta.img        --disable-verity --disable-verification
fastboot flash vbmeta_system vbmeta_system.img --disable-verity --disable-verification
```

A wiki oficial **não** o menciona. Com o bootloader desbloqueado e o
U-Boot em chainload, a verificação do AVB já não é imposta — mas gravá-lo
não faz mal e é a garantia. O `build/40-flash.sh` faz os dois, e avisa
que o vbmeta é opcional.

> ⚠️ O `dtbo` do factory **tem de ser apagado** ou briga com o do mainline.
>
> ⚠️ **Este telefone nunca se desliga de verdade**: o u-boot reinicia-o, mesmo
> a partir do seu próprio menu. Não ler um reinício como falha de desligar.
>
> 📌 **O UART deste telefone é de 1.8 V**, não 3.3 V. Um adaptador TTL de
> 3.3 V precisa de um divisor de tensão, ou o GPIO do telefone fica em
> risco. O pino de RX é puxado para cima por software no Linux e no
> U-Boot, mas para um log que sobreviva a um reinício o pull-up tem de
> ser de hardware.

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

### 4.5 O `mixer_paths` — **resolvido: `mixer_paths_wcd9375.xml`**

> ✅ **A pergunta original desta secção tem resposta.** A device tree da
> fábrica, publicada pelo projecto upstream em
> `sm7150-mainline/downstream-fdt`, dá o modelo da placa de som:
>
> ```
> sm6150_snd: sound {
>     compatible = "qcom,sm6150-asoc-snd";
>     qcom,model = "sm6150-wcd9375-snd-card";
> ```
>
> O HAL escolhe o ficheiro por esse nome: `sm6150-<variante>-snd-card` →
> `mixer_paths_<variante>.xml`. As variantes que o HAL conhece batem
> exactamente com os quatro ficheiros que existem.
>
> Portanto o board é um **`wcd9375`**, e o `mixer_paths_idp.xml` é de
> outro aparelho — apesar de o `model` de topo da device tree ser
> `"IDP"`, que é uma pista falsa: é o nome do board, não o da placa de
> som.

As quatro afinações, e o que cada uma é (ver
`rea/02-notes/audio-mixer-paths.md`):

| Ficheiro | Amplificador | Este board |
|---|---|---|
| **`mixer_paths_wcd9375.xml`** | TAS2562 | ✅ **é este** |
| `mixer_paths_idp.xml` | TAS2562 | ❌ outro aparelho |
| `mixer_paths_qrd.xml` | WSA | ❌ este board não tem |
| `mixer_paths_tavil.xml` | nenhum | ❌ |

A confirmação em runtime continua a ser útil, e é a mesma:

```sh
# no telefone, em runtime
adb shell getprop | grep -iE 'audio|mixer|platform'
# e o log do HAL na inicialização
adb logcat -b all | grep -iE 'mixer_paths|audio_platform'
```

#### ⚠️ 4.5.1 O conflito com o `alsa-ucm-conf` oficial — **a resolver antes do próximo flash**

O projecto upstream tem a sua própria configuração de áudio, no pacote
`alsa-ucm-conf-qcom-sm7150`, que o `device-qcom-sm7150` traz como
dependência. Para este board tem:

- `ucm2/Xiaomi/surya/HiFi.conf` — o perfil do altifalante;
- `ucm2/conf.d/sm8250/POCO X3.conf` — o use case que aponta para ele;
- symlinks com os nomes do fabricante (`xiaomi-XiaomiPOCOX3NFCHuaxing.conf`
  e o do Tianma), "para compatibilidade com o U-Boot".

O nosso `scripts/install-on-device.sh` escreve `HiFi.conf`, `POCO-X3.conf`
e `VoiceCall.conf` em `/usr/share/alsa/ucm2/conf.d/sm8250/`.

**O resultado, numa build actual, é este:**

| Ficheiro | De onde | O que acontece |
|---|---|---|
| `conf.d/sm8250/POCO X3.conf` | oficial | define o use case "HiFi" → `/Xiaomi/surya/HiFi.conf` (o perfil **simples**, de 18 linhas) |
| `conf.d/sm8250/POCO-X3.conf` | nosso | define "HiFi" → `/Xiaomi/surya/HiFi.conf` **e** "Voice Call" → `/Xiaomi/surya/VoiceCall.conf` |
| `conf.d/sm8250/HiFi.conf` | nosso | carregado como use case "HiFi" **à partida** — mas o `File` dos use cases aponta para `/Xiaomi/surya/`, e é lá que o perfil vai |
| `Xiaomi/surya/VoiceCall.conf` | **ninguém** | o "Voice Call" aponta para um ficheiro que nunca foi instalado |

Ou seja: **dois use cases "HiFi"** — um o simples do upstream, outro o
nosso — e **um "Voice Call" que aponta para o vazio**. A chamada pode
não ter áudio nenhum, e o routing estéreo pode não ser o nosso.

**Isto tem de ser reconciliado.** As opções, por ordem de preferência:

1. **Instalar por cima, no sítio certo.** O `POCO X3.conf` oficial é
   `POCO X3.conf` (com espaço); o nosso é `POCO-X3.conf` (com hífen). E o
   perfil tem de ir para `Xiaomi/surya/HiFi.conf`, não para
   `conf.d/sm8250/`. Escrever lá resolve os dois de uma vez, e o
   `POCO X3.conf` oficial passa a ser o ponto de entrada, com o
   "Voice Call" a mais.
2. **Remover o `alsa-ucm-conf-qcom-sm7150`** e tratar a configuração
   inteira como um overlay nosso. Mais simples, mas perde-se o que o
   upstream já tem e vai mantendo.
3. **Enviar o nosso perfil para o upstream** e usar o pacote oficial
   como está. O que é o correcto a prazo, e o que a §4.8 sugere que
   está a acontecer.


### 4.6 A IR de controlo remoto pode não existir

O HAL de IR do Android conduz `/dev/spidev0.1`, mas:

- o nó da **SPI0 está `disabled`** no DTBO e não tem dispositivo filho;
- **não há `ir-spi-led`** (nem `led-active-low`, nem `duty-cycle`) em lado
  nenhum do DTBO;
- **o kernel de fábrica não tem driver de IR** — nenhum dos 38 módulos do
  vendor, e nada no `kernel.uncompressed`.

> 📌 **Confirmado pelo projecto upstream, de forma independente.** O
> `sm7150-mainline/downstream-fdt` publica a device tree da fábrica, e o
> `fdt-surya` diz o mesmo: `spi@a80000` — a SPI0 que o HAL de IR conduz —
> está `disabled`, e a **única** SPI com um dispositivo é a `spi@880000`,
> o ecrã táctil NT36672C. Não há nenhum nó de IR nessa árvore.
>
> A wiki do projecto lista a função como **"IR TX: Broken"** — a resposta
> testada da comunidade à mesma pergunta.

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

### 4.8 Os nossos patches de foco estão a ser aceites no upstream — **mudar de estratégia**

> 📌 **Este é o achado mais importante desta secção.** Os dois patches de
> `packages/libcamera/` — o foco manual (0004) e o automático (0005) —
> foram propostos no upstream do libcamera, por outro caminho, e **já
> foram fundidos**.

| Commit upstream | Data | O que é |
|---|---|---|
| [`7231d3177`](https://gitlab.freedesktop.org/camera/libcamera/-/commit/7231d3177) `software_isp: Add focus control` | 2026-02-26 | Vasiliy Doylov — **a mesma abordagem do nosso 0004**: o sinal `setSensorControls` ganha um argumento `lensControls`, aparece o algoritmo `Af` em `src/ipa/simple/algorithms/af.cpp`, o `- Af:` entra no `uncalibrated.yaml`, e o pipeline simple chama `focusLens->setFocusPosition()` |
| [`bfcd9e133`](https://gitlab.freedesktop.org/camera/libcamera/-/commit/bfcd9e133) `libcamera: software_isp: Add variance to stats` | 2026-10-21 | Milan Zamazal — **a medida de nitidez que o nosso 0005 calcula**, chamada "variance" no upstream |
| [`a594b8900`](https://gitlab.freedesktop.org/camera/libcamera/-/commit/a594b8900) `ipa: softisp: Add Af algorithm` | 2026-10-21 | Milan Zamazal — o algoritmo `Af` para a software ISP |
| [`9d1793335`](https://gitlab.freedesktop.org/camera/libcamera/-/commit/9d1793335) `libcamera: software_isp: Add autofocus controls` | 2026-10-21 | Milan Zamazal — os controlos da lente circulam, e os valores de foco são lidos e escritos |

A revisão está na
[arquivo do libcamera-devel](https://lists.libcamera.org/pipermail/libcamera-devel/2026-February/057562.html),
com o maintainer do libcamera (Milan Zamazal, da Red Hat) a fazer a
revisão.

**O upstream está exactamente no ponto onde o nosso 0005 está.** A
mensagem do commit `a594b8900` diz isso com todas as letras: *"The
algorithm is not enabled yet because there are no autofocus stats
computed."* A variance já está nas estatísticas, mas nada a calcula
ainda. O nosso 0005 calcula uma medida de nitidez e usa-a para mexer na
lente; o upstream tem a canalização e espera pela mesma medição.

**Consequências para o plano:**

1. **O 0005 não é um patch para ficar.** É uma implementação local de
   algo que o upstream está a fazer. O estado final correcto é o upstream.
2. **O 0004 pode ser deitado fora assim que houver uma release com o
   `7231d3177`.**
3. **O overlay fixa o libcamera 0.7.1 e o pmaports actual está no
   0.7.2** — ou seja, o overlay **desactualiza** o libcamera numa build
   actual. A tag mais recente do upstream é a **v0.7.2**, e o trabalho do
   foco ainda **não está em nenhuma release**: está em `main`.
4. **Decisão a tomar:** continuar com os patches locais até sair a
   0.7.3, ou migrar já para `main` e portar o resto.

**Enquanto isso, o overlay fica como está** — os patches foram
verificados contra o 0.7.1, e o commit da base (`4b25f699`, "upgrade to
0.7.1") tem de ser o que a receita espera. É o `20-overlay.sh` que
trata disso, e o §4.5.1 do `build/README.md` explica.

Para referência, o trabalho de foco do Pavel Machek para o Librem 5 está
em `gitlab.com/tui/libcamera`, branch `l5`, e o
[fairphone6-wide-camera-linux](https://github.com/nondescriptpointer/fairphone6-wide-camera-linux)
é a referência mais próxima de um port de câmara que funcione de
verdade: pipeline completo, software ISP, auto-exposição e AWB.

---

## Parte 5 — Ordem de trabalho sugerida

Cada passo é pequeno, verificável e deixa o telefone a funcionar.

### Fase A — Desbloquear o build (sem tocar no telefone)

> 📌 **Isto já está escrito como script**, em
> [`build/`](../../build/). A fase A é `./build/run.sh`.

| # | Tarefa | Entrega |
|---|---|---|
| A1 | `fetch-upstream.sh` com o `pmaports` do GitLab | `upstream/` preenchido |
| A2 | `sudo apt install bc` e as restantes dependências | host pronto |
| A3 | Renormalizar os Subject: dos 140 patches (§4.3) | série aplicável com `git am` |
| A4 | `pmbootstrap init` + `checksum` + `install` numa imagem de stock | **imagem constrói** |
| A5 | Compilar o kernel isoladamente (§2.5) e comparar com o implantado | `vmlinuz.efi` idêntico |

> **A5 é o marco.** Se o kernel compilado daqui for bit a bit igual ao que
> está implantado no telefone, a receita está correcta e o resto é testar.
>
> 📌 **A4 tem um atalho:** as imagens semanais do
> [`sm7150-mainline/nightly-builds`](https://github.com/sm7150-mainline/nightly-builds)
> já são o resultado de uma receita que funciona. Vale a pena gravar uma
> delas **antes** de construir a nossa: dá um ponto de comparação e, se a
> nossa falhar, diz se é a receita ou o overlay.

### Fase B — A receita de deploy, de ponta a ponta

| # | Tarefa | Entrega |
|---|---|---|
| B1 | Instalar a imagem numa **segunda partição** | telefone a funcionar |
| B2 | Correr o `deploy.es.md` de 10 a 70 | **lista de onde foi preciso intervir** |
| B3 | Transformar essa lista em correcções ao `deploy.es.md` | receita corrigida |
| B4 | Repetir numa instalação limpa | **reproduzível** |

> **B4 é o que o `pending.es.md` chama de "PENDIENTE MAYOR"** e o que
> transforma "verificado no kernel e descrito no resto" em "reproduzível".
>
> ⚠️ **B1 tem de ser feito com o procedimento novo.** O esquema de
> partições mudou com a passagem para o U-Boot: **é uma instalação limpa ou
> nada** (§2.6). E o U-Boot é chainloaded pelo bootloader de fábrica, pelo
> que o telefone tem de estar desbloqueado — mas o bootloader primário
> **não** é substituído.

### Fase C — Testes por subsistema

| # | Tarefa | Entrega |
|---|---|---|
| C1 | A bateria de medições T1–T17 | tabela de resultados |
| C2 | O routing table dos microfones, transcrito do `mixer_paths` | patch do WCD9375 |
| C3 | A comutação de auscultadores a meio da chamada (§4.1) | ou arrumado, ou documentado |
| C4 | A câmara frontal: C-PHY no receptor | patch do `csiphy` |
| **C5** | **O áudio USB-C: ligar o FSA4480 à device tree** (a receita está em [`rea/02-notes/usb-c-audio-fsa4480.md`](../../rea/02-notes/usb-c-audio-fsa4480.md)) | auscultadores por cabo |
| **C6** | **Conciliar o `alsa-ucm-conf` oficial** (§4.5.1) | um só "HiFi", e o "Voice Call" a funcionar |

> 📌 **C5 é a mais barata de todas.** O driver do mainline existe, a
> config do kernel já o activa, o bus I²C já está ligado, e a device tree
> da fábrica dá o endereço, o pino e a configuração. **Falta a device
> tree e nada mais.** A receita completa, com a referência do mainline
> (`sm8350-hdk`), está em
> [`rea/02-notes/usb-c-audio-fsa4480.md`](../../rea/02-notes/usb-c-audio-fsa4480.md).
>
> 📌 **C6 tem de ser feita antes de C1**, ou os testes de áudio medem a
> configuração errada. Ver §4.5.1.

### Fase D — O que falta escrever

| # | Tarefa | Esforço |
|---|---|---|
| D1 | Driver NFC (PN557) — o formato do firmware já está decodificado | grande — ⚠️ mas a NFC já **funciona** no port oficial, ver §1.3 |
| D2 | Handshake de carregamento rápido — precisa do `usbpd` do mainline | médio |
| D3 | A-GPS no modem | médio |
| **D4** | **Migrar o foco do libcamera para o upstream** (§4.8) | médio |
| **D5** | **Câmara: porta C-PHY no receptor do SM7150** (§4.2) | **grande** — o único que é mesmo difícil |

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
