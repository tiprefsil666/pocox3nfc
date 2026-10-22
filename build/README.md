# build — a pasta do build final

Tudo o que é preciso para passar da análise à **imagem final**, e depois
testá-la no telefone. Os passos estão numerados, são independentes e podem
ser corridos um a um.

> ⚠️ **Não grave no telefone que funciona hoje.** Use uma segunda partição,
> um segundo telefone ou um cartão microSD. A receita ainda nunca foi
> executada de ponta a ponta numa instalação limpa, e um flash que não
> arranca não é um brick, mas perde-se o tempo a recuperar.

> 📌 **Este é o procedimento oficial, testado pela comunidade.** A
> [wiki do projecto](https://wiki.nura.eco/wiki/Qualcomm_SM7150_(qcom-sm7150))
> é a referência, e o `40-flash.sh` segue-a. O survey do que já está
> feito por outros está em
> [`../rea/02-notes/upstream-parallel-work.md`](../rea/02-notes/upstream-parallel-work.md).

---

## O caminho todo

```sh
cd build
./run.sh
```

Isto corre, por ordem:

| Passo | O que faz |
|---|---|
| `00-check-host.sh` | confirma que as dependências estão instaladas |
| `05-prepare-boot.sh` | descarrega o u-boot do painel certo e gera os vbmeta vazios |
| `10-fetch.sh` | clona o pmaports |
| `20-overlay.sh` | copia os quatro overlays e renormaliza a série de patches |
| `30-build.sh` | configura o pmbootstrap e constrói a imagem |
| `50-verify.sh` | confere que a imagem está bem e que o kernel e os módulos são do mesmo build |

O `40-flash.sh` fica **de fora** de propósito: grava o telefone, e isso
deve ser uma decisão, não um passo automático.

E há um passo à parte, `25-build-kernel.sh`, que compila **só o kernel** —
é o ciclo rápido para iterar sobre os patches, e está documentado abaixo.

Cada passo pode ser corrido sozinho:

```sh
./00-check-host.sh
./10-fetch.sh
./20-overlay.sh
./30-build.sh
```

Ou a partir de um ponto:

```sh
./run.sh --from 20      # a partir dos overlays
./run.sh --to 30        # só até à imagem
./run.sh --list         # a lista de passos
```

---

## O que é preciso no host

```sh
sudo apt install git python3 python3-pip bc flex bison cpio rsync \
    make gcc clang lld llvm e2fsprogs dosfstools device-tree-compiler \
    zstd openssl kpartx parted sgdisk fuse3 qemu-user-static arch-test
```

O `./00-check-host.sh` diz o que falta e dá a linha de comando. Sem
`kpartx` o pmbootstrap nem arranca; sem `qemu-user-static` o chroot não
corre os binários arm64.

Espaço: cerca de **30 GB** (o chroot, a árvore do kernel e a imagem).

---

## O que cada passo faz, e porque é assim

### `05-prepare-boot.sh` — o u-boot e os vbmeta

A imagem do pmbootstrap não traz o u-boot nem os vbmeta: são duas coisas
que o telefone precisa e que a build não produz.

O u-boot vem das releases do
[sm7150-mainline/u-boot](https://github.com/sm7150-mainline/u-boot/releases),
**um por painel**. O POCO X3 NFC veio com um ecrã **Huaxing** e outro
**Tianma**, e o u-boot errado dá **ecrã preto** — o que parece um brick e
não é.

```sh
./05-prepare-boot.sh --panel huaxing
./05-prepare-boot.sh --panel tianma
```

Para saber qual é o seu, o método da wiki — o kernel diz:

```sh
adb wait-for-device && adb reboot && adb logcat | grep "panel name is"
# imprime 'panel name is Huaxing' ou 'panel name is Tianma'
```

E como segunda opinião, o nome do dispositivo:

```sh
adb shell getprop ro.product.device
# surya         → Huaxing
# surya_tianma  → Tianma
```

Os vbmeta são **gerados**, não copiados do firmware: um vbmeta vazio com
o `avbtool` desliga o verified boot. O `avbtool` é Apache-2.0 e é um
ficheiro só. A wiki oficial não os menciona — com o bootloader
desbloqueado e o U-Boot em chainload a verificação do AVB já não é
imposta — mas gravá-los não faz mal e é a garantia.

> 📌 **O U-Boot é *chainloaded* pelo bootloader de fábrica.** O bootloader
> primário **não** é substituído: o U-Boot vai para a partição `boot` e a
> Xiaomi arranca-o. E o **esquema de partições mudou completamente** com
> a passagem para o U-Boot: o esquema antigo e o novo são incompatíveis e
> **não há migração**. É uma instalação limpa ou nada.

### `10-fetch.sh` — o pmaports e o pmbootstrap

Dois clones rasos:

| | De onde | Versão |
|---|---|---|
| pmaports | [gitlab.postmarketos.org/postmarketOS/pmaports](https://gitlab.postmarketos.org/postmarketOS/pmaports.git) | `main` |
| pmbootstrap | [gitlab.postmarketos.org/postmarketOS/pmbootstrap](https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git) | **`3.12.1`**, fixada |

O pmbootstrap **não está neste repositório** — é uma ferramenta de
terceiros — e a versão importa: o `init` do 3.12.1 é interactivo, e é
por isso que o `30-build.sh` escreve a configuração em vez de a
responder. Uma versão diferente pode tratar as coisas de outra maneira, por isso
o tag é fixado e verificado.

O commit usado fica registado em `out/pmaports-version.txt`, para
qualquer imagem poder ser rastreada até à origem.

### `20-overlay.sh` — os quatro overlays

| Overlay | Onde | Para quê |
|---|---|---|
| `linux-postmarketos-qcom-sm7150` | `device/community/` | os 140 patches, a receita e a config |
| `libcamera` | `temp/` | o foco automático |
| `libqmi` | `temp/` | as mensagens das constelações GNSS |
| `hexagonrpcd` | `temp/` | o PD de áudio do ADSP e o registo de sensores |

> 📌 **Onde fica o pacote do kernel mudou.** A receita do `surya-pmos`
> apontava para `device/testing/`, que era onde vivia na altura. O pmaports
> actual põe-no em `device/community/`. O passo procura-o em `device/*/` e
> escreve o caminho encontrado no `env.sh`, para que não se partija a meio
> de um build.

O `libqmi` e o `hexagonrpcd` **não estão no pmaports**: constroem-se a
partir de `temp/`. O `libcamera` já lá está.

> 📌 **O `libcamera` é fixado a um commit.** A receita do overlay é um
> *fork* da receita do pmaports, com os nossos dois patches (0004 e 0005)
> por cima dos três que a distribuição tinha na altura. A distribuição
> Entretanto **removeu os patches do PinePhone, renomeou os outros e
> mudou os ficheiros de ajuste dos sensores** — por isso o pmaports actual
> não satisfaz os `sha512sums` da receita, e o build falhava nos fontes
> em falta.
>
> A base é extraída do commit `4b25f699` ("temp/libcamera: upgrade to
> 0.7.1"), que é o estado exacto para o qual a receita foi escrita: os
> mesmos três patches, os mesmos ficheiros de ajuste, o mesmo
> `qcam.desktop`, todos com os `sha512sums` a bater.

> 📌 **Um patch estava com o nome errado.** O `0005` chamava-se
> `0005-libcamera-soft-contrast-detection-autofocus.patch` no directório,
> mas a receita listava `0005-libcamera-soft-one-shot-contrast-detection-autofocus.patch`.
> O conteúdo era o certo — o `sha512` batia — mas o nome não, e o build
> procurava pelo nome. Corrigido: o ficheiro passou a ter o nome que a
> receita sempre disse.

> 📌 **Os dois patches de foco já estão a ser aceites no upstream do
> libcamera.** O `7231d3177` ("software_isp: Add focus control") é a
> mesma abordagem do nosso 0004, e o `bfcd9e133` ("software_isp: Add
> variance to stats") é a medida de nitidez que o nosso 0005 calcula.
> Estão fundidos, mas **ainda em nenhuma release** — a tag mais recente é
> a v0.7.2, e o nosso overlay fixa a **0.7.1**, que o pmaports actual já
> não usa.
>
> Isto é uma decisão a tomar, não um bug a corrigir: continuar com os
> patches locais até sair a 0.7.3, ou migrar já para o `main` do
> libcamera. Ver o roadmap §4.8.

**A renormalização da série.** Os 140 patches trazem o seu `Subject:`
com um contador inconsistente: 30 deles perderam-no (`[PATCH]` em vez de
`[PATCH N/M]`) e os denominadores estão errados (`/106`, `/113`, `/2`). O
`APKBUILD` só se importa do nome dos ficheiros, por isso o build do
pmbootstrap funciona de qualquer maneira — mas o `git am` não, porque os
índices não formam uma série contínua. Este passo reescreve a linha
`Subject:` para `[PATCH N/140]` e **não toca em mais nada**: os diffs
ficam exactamente como estavam.

### `30-build.sh` — o pmbootstrap

Este pmbootstrap é o **3.12.1**, e o `init` dele é **interactivo**: pergunta
o caminho do work, o do pmaports, o canal, o dispositivo, o keymap, o
utilizador, a UI, o gestor de serviços, a timezone, o locale, o hostname,
as chaves SSH e os pacotes extra — catorze perguntas, todas capazes de
ser respondidas errado por um script.

A configuração é um ficheiro INI simples, por isso este passo **escreve-a
directamente** e o build nunca tem de ser respondido. E usa a sua própria
configuração (`build/out/pmbootstrap_v3.cfg`) em vez da global em
`~/.config/`, para que este projecto não atrapalhe outro — e para que as
definições do build fiquem gravadas com ele.

```sh
[pmbootstrap]
aports = /caminho/absoluto/para/pmaports
device = qcom-sm7150
kernel = postmarketos-qcom-sm7150
ui = postmarketos-ui-plasma-mobile
work = /caminho/absoluto/para/build-pmb
build_default_device_arch = False
...
```

Três coisas que custam uma noite se não se souber:

1. **`work` e `aports` têm de ser absolutos.** O pmbootstrap guarda-os na
   configuração e usa-os em todos os comandos seguintes; um caminho
   relativo quebra a meio.

2. **`build_default_device_arch False`.** Este pmbootstrap compila o
   pacote do dispositivo para a arquitectura do host por omissão, o que
   está errado para um `arm64`.

3. **`pmbootstrap shutdown` entre o `checksum` e o `install`.** O
   `checksum` deixa o chroot montado, e o build seguinte falha com
   *"Failed to umount … /mnt/pmbootstrap/packages"*.

E um quarto, sobre o kernel: **kernel e módulos têm de ser a mesma
compilação**. Um `vmlinuz` novo com os módulos velhos dá um telefone que
**arranca, chega ao `greetd` e morre em silêncio aos ~25 s**, sem Oops e
sem nada no `ramooops` — porque o `CONFIG_MODVERSIONS` está desligado e
nada detecta o desajuste. O `50-verify.sh` verifica exactamente isto.

### `25-build-kernel.sh` — só o kernel, para iterar

A imagem inteira demora entre 20 e 90 minutos. O kernel sozinho demora
uns 15, e é o ciclo a usar enquanto se persegue um patch.

```sh
./25-build-kernel.sh              # descarrega o fonte e compila
./25-build-kernel.sh --no-fetch   # compila o que já lá está
./25-build-kernel.sh --clean      # deita a árvore fora
### `40-flash.sh` — gravar

```sh
./40-flash.sh          # só mostra o que ia fazer
./40-flash.sh --run    # grava
```

Se o ecrã ficar preto, **não é um brick**: é o u-boot ou a device tree
errados. Para voltar ao Android:

```sh
fastboot flash boot boot.img    # do pacote de firmware da Xiaomi
fastboot reboot
```

### `50-verify.sh` — confirmar

Confere que a imagem existe, que o release do kernel **não tem um `+`** (o
`LOCALVERSION=` no build é o que o evita, e sem ele o directório dos
módulos não corresponde), que o `lib/modules/<release>` existe, e que os
pacotes sobrepostos são os que se esperava.

Com um telefone a correr:

```sh
./50-verify.sh --device surya.local
```

---

## Depois de gravar: a configuração do dispositivo

A imagem não traz a configuração de áudio, nem o wireplumber, nem os
serviços. Isso instala-se à parte:

```sh
surya-pmos/scripts/install-on-device.sh <host-ou-ip>
```

> ⚠️ **O `alsa-ucm-conf-qcom-sm7150` oficial colide com a nossa configuração
> de áudio.** O pacote oficial — que o `device-qcom-sm7150` traz como
> dependência — instala o perfil em `Xiaomi/surya/HiFi.conf` e o use case
> em `conf.d/sm8250/POCO X3.conf` (**com espaço**). O nosso
> `install-on-device.sh` escreve por cima de ambos, no sítio certo, e
> limpa os ficheiros nossos que ficariam a mais.
>
> Sem isso, uma build actual fica com **dois use cases "HiFi"** a
> competir, e o "Voice Call" a apontar para um `VoiceCall.conf` que nunca
> foi instalado. Ver o roadmap §4.5.1.

---

## Os testes

Em `tests/`. A bateria completa:

```sh
tests/bateria-de-testes.sh --list   # o que é cada teste
tests/bateria-de-testes.sh          # os objectivos
```

Os guiões que o `deploy.es.md` §10 citava e que nunca foram commitados
estão aqui reconstruídos: `caza-loteria.sh` (T1) e
`verify-call-routing.sh` (T2). O `estado/verificar.sh` (T17) também.

| | Teste | Como |
|---|---|---|
| T1 | Estéreo L/R | `tests/caza-loteria.sh` — ao ouvido |
| T2 | Auricular do telefone | `tests/verify-call-routing.sh` — objectivo |
| T3 | Chamada, áudio nos dois sentidos | ao ouvido |
| T4 | Volume por destino | ao ouvido |
| T5 | Mover a chamada para o altifalante | ao ouvido — ⚠️ sabe-se que falha |
| T6 | Mover a chamada de volta | ao ouvido — ⚠️ sabe-se que falha |
| T7 | Auscultadores BT | `tests/bt-offload.sh` — objectivo |
| T8 | Aurora cancelada | medição — ⚠️ precisa da calibração de fábrica |
| T9 | Câmara traseira | `tests/camera.sh traseira` |
| T10 | Câmara frontal | `tests/camera.sh frontal` — ⚠️ sabe-se que não há fluxo |
| T11 | Suspensão | `tests/suspensao.sh` |
| T12 | Bateria | `tests/bateria.sh` |
| T13 | GNSS | `tests/gnss.sh` |
| T14 | Notificações | ao ouvido |
| T15 | USB OTG | `tests/usb-otg.sh` |
| T16 | Arranque a frio | `tests/arranque-frio.sh` |
| T17 | Estabilidade | `tests/estado/verificar.sh` |

---

## Onde ficam as coisas

```
build/
├── env.sh              as definições: device, kernel, ui, caminhos
├── lib.sh              o log e as funções comuns
├── run.sh              o orquestrador
├── 00-check-host.sh    dependências
├── 05-prepare-boot.sh  u-boot e vbmeta
├── 10-fetch.sh         pmaports
├── 20-overlay.sh       os quatro overlays
├── 25-build-kernel.sh  só o kernel, para iterar
├── 30-build.sh         o pmbootstrap
├── 40-flash.sh         gravar o telefone
├── 50-verify.sh        conferir
├── tests/              a bateria de testes
└── out/                os logs e o manifesto (não vai para o Git)
```

Os logs de cada passo ficam em `out/logs/`, e o `out/manifest.txt` diz com
que pmaports e com que data a imagem foi construída.

---

## Diagnóstico

```sh
# o estado de cada etapa
$PMB status

# o log completo
$PMB log > build.log 2>&1

# limpar tudo e recomeçar
$PMB zap
```

| Sintoma | Causa provável |
|---|---|
| *"Can't find all programs required to run pmbootstrap: kpartx"* | falta o `kpartx`; o pmbootstrap nem arranca sem ele |
| *"Run 'pmbootstrap init' first"* | a config não foi escrita; correr `30-build.sh --config` |
| *"Your work folder version needs to be migrated"* | falta o ficheiro `version` no work dir; o `30-build.sh` escreve-o |
| *"Failed to unmount … /mnt/pmbootstrap/packages"* | faltou o `pmbootstrap shutdown` depois do `checksum` |
| *"up to date"* num pacote que devia reconstruir | o `pkgrel` não foi incrementado no `APKBUILD` |
| O `libcamera` falha nos fontes | o `20-overlay.sh` tem de correr: ele é que extrai a base do commit fixado |
| O telefone arranca e morre aos ~25 s | kernel e módulos de builds diferentes |
| O directório dos módulos não corresponde | o kernel foi construído sem `LOCALVERSION=` |
| Ecrã preto depois do flash | o u-boot é do outro painel, ou o `dtbo` não foi apagado |
| A imagem é `arm64` mas o host é `x86_64` e nada corre | falta o `qemu-user-static` |

---

## O que ainda não foi testado

Esta pasta foi escrita contra o pmbootstrap 3.12.1 e contra o pmaports
actual, e os passos que não precisam de root foram corridos até ao fim:
a verificação do host, o download do u-boot, a geração dos vbmeta, os
clones do pmaports e do pmbootstrap, a cópia dos overlays com a
renormalização da série, e a escrita da configuração do pmbootstrap
(confirmada com `pmbootstrap status`).

A cadeia completa — `10-fetch` → `20-overlay` → `30-build --config` — foi
corrida a partir de um **clone limpo** do repositório, e é isso que a
secção acima descreve.

**O build completo — o `checksum` e o `install` — ainda não foi corrido de
ponta a ponta.** Precisa de root, e de um host com as dependências
instaladas. É o primeiro passo a dar, e o `30-build.sh` está feito para
isso: `./run.sh --from 30`.
| *"Failed to umount … /mnt/pmbootstrap/packages"* | faltou o `pmbootstrap shutdown` depois do `checksum` |
| *"up to date"* num pacote que devia reconstruir | o `pkgrel` não foi incrementado no `APKBUILD` |
| O telefone arranca e morre aos ~25 s | kernel e módulos de builds diferentes |
| O directório dos módulos não corresponde | o kernel foi construído sem `LOCALVERSION=` |
| Ecrã preto depois do flash | o u-boot é do outro painel, ou o `dtbo` não foi apagado |
| A imagem é `arm64` mas o host é `x86_64` e nada corre | falta o `qemu-user-static` |
