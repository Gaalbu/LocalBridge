# Protocolo LocalBridge v1

Este documento descreve o comportamento implementado. O protocolo usa HTTP sem criptografia na rede local e não autentica a identidade criptográfica dos peers.

## Descoberta

Cada instância anuncia `_localbridge._tcp` por Zeroconf/mDNS com identificador, nome, plataforma, porta e versão do protocolo. O cliente confirma disponibilidade e compatibilidade com `GET /api/v1/ping`. Quando multicast não funciona, o usuário pode informar `IP:porta` manualmente.

## Conexão e pedido

O remetente chama `POST /api/v1/transfer/request` com sua identidade declarada, a lista de arquivos e o tamanho total. O handshake é limitado a 256 KiB e 100 arquivos. O destinatário apresenta o pedido ao usuário e aguarda aceite por até dois minutos.

Um aceite cria uma sessão UUID temporária, válida por 30 minutos e limitada aos IDs de arquivo aprovados. A sessão funciona como autorização por posse do identificador; ela não comprova a identidade do remetente.

## Transferência

Para cada arquivo aceito, o remetente envia bytes em stream para:

```text
POST /api/v1/transfer/{sessionId}/file/{fileId}
Content-Type: application/octet-stream
Content-Length: tamanho declarado
```

O receptor valida sessão e ID, limita o tamanho recebido, sanitiza o nome, grava em `.part`, verifica SHA-256 quando fornecido e só então renomeia o arquivo. Arquivos existentes não são sobrescritos. Os uploads são sequenciais e não há retomada por offset.

## Confirmação

`GET /api/v1/transfer/{sessionId}/complete` retorna `completed` somente quando todos os arquivos aprovados foram recebidos. Uma sessão incompleta retorna conflito e informa apenas contagens, sem revelar caminhos locais.

## Erros relevantes

| Status | Condição |
|---|---|
| `403` | pedido recusado ou expirado |
| `404` | sessão ou arquivo desconhecido |
| `409` | arquivo já recebido ou sessão incompleta |
| `413` | tamanho diferente do declarado |
| `422` | JSON, metadados ou checksum inválido |
| `500` | falha de escrita ou erro interno |

Arquivos parciais são removidos após falhas tratadas de upload.

## Modelo de confiança atual

O usuário deve operar em uma LAN confiável e confirmar cada pedido. O tráfego não possui TLS nem criptografia de payload; participantes da rede podem observar o conteúdo e um atacante local pode tentar obter identificadores de sessão. mDNS e os campos de identidade são informativos, não autenticados.

Hardening futuro deve usar protocolos revisados e bibliotecas consolidadas para pareamento, autenticação e criptografia. O projeto não deve implementar criptografia própria.
