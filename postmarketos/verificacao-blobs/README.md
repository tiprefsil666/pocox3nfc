# Verificação de blobs — POCO X3 NFC (surya / SM7150)

Inventário para engenharia reversa comparando a extração Android local com o estado conhecido do port postmarketOS. O objetivo é identificar dependências e lacunas por subsistema; presença de um blob no firmware **não** significa que o port precisa dele nem que seja seguro/compatível carregá-lo no Linux mainline.

## Fontes e método

- Firmware de referência: `../../android/extracted/rootfs/vendor/` e módulos extraídos; inventário SHA-256 original em `../../android/extracted/blob-inventory.csv`.
- `blob-index.csv` é um recorte temático do inventário original; cada linha conserva caminho relativo a `vendor/`, tamanho e SHA-256. Um arquivo pode aparecer em mais de uma categoria por causa do nome.
- Imagem postmarketOS disponível em `../20261009-0834-postmarketOS-v26.06-plasma-mobile-6-qcom-sm7150.img`; detalhes e hash em `../PREBUILT.md`. É uma imagem genérica SM7150, não evidência de que todos os recursos funcionem no Surya.
- Estado do overlay comunitário consultado em 2026-10-14: [woodyst/surya-pmos](https://github.com/woodyst/surya-pmos). É um port hobbyista, e o próprio README informa que a receita completa ainda não foi validada numa instalação limpa.

## Legenda

- **Portado**: o overlay/port reporta a função operacional; não implica ausência de firmware proprietário.
- **Parcial**: há suporte funcional, mas com limitações conhecidas.
- **Investigação**: faltam evidências locais de suporte no prebuild ou o estado precisa de validação no aparelho.
- **Não redistribuído**: o overlay depende de dados/firmware de fábrica mantidos no próprio aparelho.

## Matriz inicial

| Subsistema | Estado no port Surya consultado | O que a extração Android pode revelar | Próximo trabalho de engenharia reversa |
|---|---|---|---|
| Bateria / carregamento / energia | Portado: leitura de carga, carregamento, gauge OCV compensado e suspend melhorado. Carga Xiaomi 33 W ainda sem handshake proprietário. | HAL health/power, thermal, configuração de carregador e serviços Qualcomm/Xiaomi. | Correlacionar fuel gauge e BQ2597x (ID exato pendente: wiki nomeia BQ25968; DT Android usa compatível de família) com limites de corrente e fontes sysfs/IIO; comparar leituras sob carga e repouso. |
| Câmeras | Traseira com foto/vídeo e autofocus reportada; câmera frontal sem fluxo; qualidade sem tuning ISP e zoom limitado. | HALs Android e configuração/tuning dos sensores: IMX682, S5K3T2, HI1337, HI259, OV02B1B/GC02M1B e variantes OEM. | Mapear sensores, endereços I²C, lanes/clock/reset/reguladores no DT; capturar init sequences e comparar libcamera. Prioridade alta: frontal e tuning da traseira. |
| Áudio / chamadas | Parcial/portado: estéreo, auricular, headset e áudio de chamadas; distorção no speakerphone máximo. Cancelamento de eco exige calibração de fábrica local, não distribuída. | HALs, mixer paths, ACDB, firmware DSP/ADSP, codecs/amplificadores (WCD/TAS/WSA). | Documentar calibrações e roteamento, mapear controles ALSA/SLIMbus e comparar ACDB. Não publicar calibração pessoal ou dados sensíveis. |
| Sensores / vibração | Acelerômetro, luz, proximidade e magnetômetro reportados; vibração fraca. | HAL SSC e calibração/configuração Qualcomm, lista de sensores e init scripts. | Associar cada sensor a driver IIO/input, DT e evento Android; identificar frequência ressonante e controles do atuador linear. |
| GNSS / modem / dados móveis | Chamadas, LTE/SMS e GNSS reportados; constelações Galileo/BeiDou expostas; sem A-GPS. | Serviços QMI, GNSS, modem, IPA e configuração de rádio. | Traçar interfaces QMI/QRTR e origem de NMEA; estudar assistência A-GPS e registrar estado de banda/IMS sem divulgar identificadores. |
| Wi‑Fi / Bluetooth | Wi‑Fi não detalhado no resumo do overlay; Bluetooth headset/A2DP e chamadas reportados, com falhas de recuperação ainda descritas. | Módulos WLAN/BT Qualcomm, firmware e serviços de calibração/configuração. | Confirmar driver e firmware efetivamente usados no prebuild; revisar dumps, coexistência e recovery do controlador. |
| Tela / toque | Imagem genérica SM7150 exige variante certa; Surya possui painéis Huaxing e Tianma. | Perfis DSI das duas variantes e serviços proprietários de display/touch. | Identificar variante física; mapear DT/pinctrl/reguladores e controlador touch. Evitar misturar DTB de painéis. |
| NFC | Investigação: não confirmado no estado descrito do overlay. | Serviço e configuração NXP/NQ; firmware/configs RF. | Identificar chip/transporte I²C ou SPI, IRQ e firmware carregado; procurar implementação Linux/driver compatível. |
| USB / OTG | Host USB OTG reportado, testado com webcam. | Configuração de gadget/USB e serviços vendor. | Validar modo host/device, papel USB-C, carregamento e DT. |

## Priorização sugerida

1. Câmera frontal e dados de tuning/sequence dos sensores.
2. Áudio: ACDB/DSP, mixer e caminhos dos amplificadores.
3. Bateria/carga: fuel gauge, identificar BQ2597x por PART_INFO e limites/handshake de potência.
4. Display e touch por variante de painel.
5. Wi‑Fi, NFC, GNSS e vibração, confirmando primeiro hardware e estado no aparelho.

## Cuidados de interpretação

Os blobs Android são referências para entender protocolo, tabelas, calibração e sequência de inicialização. HALs Android e módulos compilados para o kernel/vendor Android geralmente não são drivers Linux mainline reutilizáveis diretamente. O README do overlay lista firmware proprietário necessário (incluindo ACDB, DSP e configuração de sensores) e diz que não é redistribuído. Preserve a procedência e licenças; mantenha calibrações e dumps com identificadores fora de commits públicos.

Para registrar cada achado, anote caminho/offset, SHA-256, ferramenta/versão, hipótese, evidência observada e grau de confiança. Use `blob-index.csv` como índice de busca, não como declaração de que todo arquivo listado é relevante.
