# tests — a bateria de testes

Os testes que o `ROADMAP-pt.md` §3.3 define, com guiões que se possam
correr. O `deploy.es.md` §10 citava `caza-loteria.sh`,
`verify-call-routing.sh` e `estado/verificar.sh`, mas nunca foram
commitados — estão aqui reconstruídos.

## Como correr

Estes guiões correm **no telefone**, não no computador. O caminho normal:

```sh
# do computador
scp -r build/tests surya.local:~/

# no telefone
cd ~/tests
./bateria-de-testes.sh
```

Ou, a partir do computador, por ssh:

```sh
ssh surya.local '~/tests/bateria-de-testes.sh'
```

## A lista

```sh
./bateria-de-testes.sh --list
```

## Os dois tipos

**Objectivos** — um guião decide se passaram. São `verify-call-routing.sh`,
`bt-offload.sh`, `suspensao.sh`, `bateria.sh` (a bateria), `gnss.sh`, `usb-otg.sh`,
`arranque-frio.sh` e `estado/verificar.sh`.

**Ao ouvido** — uma pessoa tem de escutar e responder. São `caza-loteria.sh`
(T1), a chamada real (T3, T4, T5, T6), o eco (T8) e as notificações (T14).
Estes guiões imprimem o procedimento e esperam.

## As regras do `caza-loteria.sh`

Tom de amplitude **≤ 30 %** e **≤ 20 s**, nunca secções longas em loop. É
a diferença entre testar e magoar alguém.

## O que se sabe que falha

Estes testes **não** são um relatório de sucesso: dois deles são
conhecidamente falhados, e o guião diz isso em vez de o esconder.

| Teste | Estado |
|---|---|
| T5, T6 — mover a chamada entre altifalante e auscultadores | ⚠️ sabe-se que a volta aos auscultadores fica muda. Ver `surya-pmos/docs/ROADMAP-pt.md` §4.1 |
| T8 — cancelamento de eco | ⚠️ precisa da calibração de voz de fábrica, que é da Xiaomi e não é redistribuída |
| T10 — câmara frontal | ⚠️ o S5K3T2 transmite em C-PHY e o receptor está em D-PHY. Ver §4.2 |

O `camera.sh frontal` sai com **0** de propósito: é um bloqueador
conhecido, não uma falha nova. A distinction importa — se falhar por
outra razão, a frente tem de ser investigada.

## Guardar a evidência

O runner chama-se `bateria-de-testes.sh` e o teste da bateria chama-se
`bateria.sh` — em português as duas coisas se chamam "bateria", e era
preciso não as confundir.

O `estado/verificar.sh --save` escreve um ficheiro com o resultado e o
kernel. Vale a pena guardar cada execução com a data, porque o critério
de aceitação é ter a tabela T1–T17 preenchida com evidência objectiva de
cada resultado.

## Quando um teste falha

1. **Não reiniciar de imediato.** O `pstore` guarda o rasto:
   `/sys/fs/pstore/`. Um reinício apaga o `dmesg`.
2. `dmesg | grep -iE 'oops|warn|BUG|panic'`
3. `journalctl -b -1`
4. `cat /sys/fs/pstore/*`
