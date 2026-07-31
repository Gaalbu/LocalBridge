# Arquitetura

## Decisões

Cada instalação exerce simultaneamente os papéis de servidor e cliente. Não existe backend central: descoberta e tráfego ficam na LAN.

O documento inicial sugeria `multicast_dns`, mas esse pacote implementa consultas e não anúncio. A implementação usa `bonsoir`, que cobre descoberta e anúncio Zeroconf em Android e Linux e fornece endereços já resolvidos.

## Camadas

- `domain`: identidade, peer, arquivo e estados de transferência sem dependência de UI;
- `data/network`: anúncio/descoberta, servidor Shelf e cliente HTTP;
- `data/settings`: identidade e pasta persistidas localmente;
- `application`: orquestra ciclo de vida, aprovação, fila e progresso com Riverpod;
- `presentation`: Material 3, drag-and-drop, share intent, configurações e dialogs.

## Protocolo v1

1. `_localbridge._tcp` anuncia ID, nome, plataforma, porta e versão.
2. `GET /api/v1/ping` elimina anúncios inacessíveis ou incompatíveis.
3. `POST /api/v1/transfer/request` envia apenas metadados.
4. O receptor aceita ou recusa; uma sessão UUID temporária autoriza arquivos específicos.
5. `POST /api/v1/transfer/{sessionId}/file/{fileId}` transmite bytes crus com `Content-Length`.
6. O receptor escreve em `.part`, limita o stream ao tamanho declarado, valida e renomeia.
7. `GET /api/v1/transfer/{sessionId}/complete` confirma a sessão.

## Limites e invariantes

- handshake: 256 KiB e no máximo 100 arquivos;
- pedido de aceite: 2 minutos;
- sessão: 30 minutos;
- upload sequencial para limitar I/O e memória;
- nomes nunca são usados sem `basename` e sanitização;
- arquivos existentes não são sobrescritos;
- nenhuma resposta expõe a pasta local de destino.

## Evolução esperada

Antes de protocolo v2, priorize autenticação por pareamento, TLS ou criptografia de payload, retomada via offsets e foreground service no Android. Mudanças de wire format precisam preservar v1 ou incrementar `protocolVersion`.
