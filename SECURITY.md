# Política de segurança

## Versões suportadas

Enquanto o projeto estiver em `0.x`, somente o código mais recente da branch `main` recebe correções de segurança.

## Reportar uma vulnerabilidade

Não abra uma issue pública com detalhes exploráveis. Use **Security > Report a vulnerability** no GitHub do repositório. Inclua versão, plataforma, impacto, passos mínimos de reprodução e, se possível, uma correção sugerida.

## Modelo de ameaça do MVP

A LocalBridge foi projetada para uma LAN pessoal confiável:

- solicitações precisam de aceite explícito no dispositivo receptor;
- metadados têm tamanho e quantidade limitados;
- nomes são sanitizados e nunca determinam caminhos fora da pasta configurada;
- uploads só são aceitos para IDs previamente autorizados e expiram;
- arquivos são gravados como `.part`, conferidos e só então renomeados;
- o app não abre nem executa automaticamente arquivos recebidos.

O protocolo usa HTTP sem TLS na rede local. Um participante malicioso da mesma LAN pode observar ou alterar tráfego. Até existir autenticação e criptografia ponta a ponta, não use o app em Wi-Fi público, empresarial hostil ou com dispositivos não confiáveis.

## Segredos

Nunca versione keystores, `key.properties`, tokens, `.env`, credenciais Firebase, certificados ou arquivos pessoais transferidos. Se um segredo for commitado, revogue/rotacione primeiro e depois remova-o do histórico.
