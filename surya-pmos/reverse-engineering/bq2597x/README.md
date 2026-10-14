# BQ2597x / BQ25968 — análise inicial dos blobs Android

**Escopo:** firmware local MIUI `V12.0.6.0.QJGMIXM` (Android 10), incluído neste workspace. Apenas análise estática; o driver do chip não foi executado e não há leitura I²C/runtime do aparelho nesta sessão.

## Resultado mais importante: identificar o sufixo real do chip

A tabela DTBO do firmware contém cinco entradas com o nó `bq2597x-charger@65`; todas usam `compatible = "ti,bq2597x-standalone"`, endereço I²C `0x65`, IRQ GPIO 43, active-low/falling edge e as mesmas opções de proteção. O firmware, portanto, identifica **a família e o modo**, não o sufixo exato (`68`, `70`, `71`). Veja [`android-dtbo-node.dts`](android-dtbo-node.dts) e [`dtbo-matches.csv`](dtbo-matches.csv).

O kernel downstream extraído contém strings do driver `bq2597x` (incluindo `bq2597x-STANDALONE`, erros de leitura do ID e logs de registos), o que confirma que o driver está compilado no kernel Android. O blob `batterysecret` é outro componente: trata de USB-PD/HVDCP, estados do USB-C e verificação de PD; ele não programa diretamente os registos do charge pump.

A ficha oficial da TI para o BQ25968 documenta o registo `PART_INFO` em `0x13`; os bits inferiores `[3:0]` distinguem `0x0 = BQ25970`, `0x1 = BQ25971` e `0x6 = BQ25968`. Assim, **uma leitura em runtime de `PART_INFO & 0x0f` resolve o nome exato**. A tabela da wiki dizer BQ25968 e o overlay Surya ter um driver etiquetado BQ25970 são pistas divergentes, não prova de que o ID observado seja 0 ou 6. Fonte primária: [datasheet TI BQ25968, seção 9.6.1.20 / registo PART_INFO](https://www.ti.com/lit/ds/symlink/bq25968.pdf).

## Configuração decodificada no DTBO (entrada zero-based 7)

- Barramento: fragmento aplica em `&qupv3_se9_i2c`.
- Endereço do dispositivo: `0x65`.
- IRQ: GPIO 43, flag `0x02` (trigger de borda de descida no binding downstream).
- `pinctrl-names`: `bq_charger_active`, `bq_charger_suspend`.
- Desabilitados no firmware: alarme BAT OVP, BAT OCP, alarme BAT OCP, alarme/limite BAT UCP e proteções térmicas TS_BAT, TS_BUS e T_DIE.
- Limiares codificados no DT (hex → decimal): BAT OVP `0x11c6 → 4550`; BAT OVP alarm `0x1162 → 4450`; BUS OVP `0x2ee0 → 12000`; BUS OVP alarm `0x2af8 → 11000`; BUS OCP `0x0dac → 3500`; BUS OCP alarm `0x0ce4 → 3300`; BAT/BUS therm `0x15 → 21`; DIE therm `0x91 → 145`; AC OVP `0x0e → 14`.

Os nomes das propriedades e os números batem com os campos familiares expostos no device tree downstream; `mV`, `mA`, percentual TS e °C são interpretações consistentes com esse driver/configuração, não unidades armazenadas no FDT. Os cinco nós têm valores idênticos. Não habilite proteções de termistor em mainline sem confirmar ligação/configuração das entradas: o overlay Surya comenta que as entradas térmicas do charge pump são flutuantes nessa placa.

## Android userspace relevante

`vendor/bin/batterysecret` foi aberto no REA MCP/Hopper:

- SHA-256 do ELF ARM64: `8f12eeb8f77bb9cec47e73cb4639c3b598137d012fccb882f575ceb146946140`.
- O MCP encontrou paths e estados de USB-PD (`real_type`, `current_state`, `current_pr`, PDO, SVID, `verify_process`, `usbpd_verifed`) e `USB_HVDCP_3`.
- A rotina principal processa eventos USB; só quando recebe `POWER_SUPPLY_NAME=usb` e `DATA_ROLE=ufp` lê `real_type` e segue o ciclo de eventos. Outra rotina espera estados `UNKNOWN`, `SNK_Ready` ou `SRC_Ready` e envia/verifica dados de PD. O pseudocódigo recuperado é análise estática; os nomes internos das funções estão sem símbolos e não devem ser tratados como source original.
- IDs REA para reconsulta: overview `ev_6062d8ed2ed63e2b65f8641a0a15ae03ec09a20022535179f0cc1b38b51dfa50`; strings HVDCP `ev_f91a30c597c22b886a428138d9dad4400fd9ce7c62d21912e8fd33c1225512f5`; rotina de evento/PD `ev_78a57e2e94336fdd111eabff3d49b11b34919ddb97b937c26b77c13576d7c1a8`; rotina de estados `ev_fc5343f5799854c8aa3237713a2ff1937e88532b59aa0cf9264d9480c9872953`.

Isso separa duas partes: o charge pump converte VBUS alto em corrente para a bateria; o protocolo com o adaptador/USB-PD/HVDCP negocia para obter VBUS acima de 5 V. `batterysecret` é uma pista para a segunda parte, não um substituto do driver I²C. A implementação mainline do overlay descreve esse handshake proprietário como ainda faltante.

## Compatibilidade com o overlay local

O patch `../../kernel/0002-power-supply-add-TI-BQ25970-switched-capacitor-charg.patch` usa o compatible de família `ti,bq2597x-standalone` e lê `PART_INFO` (`0x13`) antes de inicializar. Ele aceita IDs `0x0` (BQ25970) e `0x6` (BQ25968), atribui o nome de modelo correto e recusa outros IDs. A revisão comparou os registos efetivamente usados pelo driver com o mapa TI do BQ25968; o registo `0x0A`, que diverge como `CONVERTER_STATE` nesse chip, não é acessado.

Ainda falta confirmação no aparelho físico do nibble lido e da sequência de inicialização sob postmarketOS. A negociação Xiaomi HVDCP/USB-PD também continua fora do driver, portanto a presença deste suporte não habilita por si só carga rápida. Antes de ajustar proteções térmicas e limites do hardware, compare a configuração Android e o downstream 4.14 com as ligações reais da placa. Os detalhes do handshake devem ser reconstruídos separadamente a partir de `batterysecret`, `hvdcp` e serviços USB.

## Procedência local

- DTBO original: `../../../android/firmware-update/dtbo.img`, SHA-256 `293519d0abe403e805db3a2f7233760a6b4ef5f96e45484419872ee2bd023cd6`.
- Kernel Android uncompressed: `../../../android/extracted/boot/kernel.uncompressed`, SHA-256 `b2d4c78a78f79a6810d41709731768dab914bbe9c057b7f5f874045c6cdb7662`.
- O DTBO tem header Android magic `0xd7b7ab1e`, 27 entradas, tabela a partir do offset 32 e página 4096; os offsets/tamanhos das cinco entradas estão em `dtbo-matches.csv`.
- Conversão usada para validar o recorte: `dtc -I dtb -O dts`. Arquivos fonte permanecem intactos.

## Limite atual das ferramentas MCP

O MCP REA/Hopper analisou o ELF `batterysecret`. O provider REA para Binwalk recusou a inspeção de firmware por falta de `REA_BINWALK_COMMAND`, e o provider Ghidra não está configurado. A tabela FDT foi portanto extraída localmente com o header Android DTBO e `dtc`; não houve disassembly do kernel Android pelo MCP. Isso é uma limitação explícita da cobertura MCP, não ausência de dados no firmware.
