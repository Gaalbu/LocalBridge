# Manutenção

## Custo

O aplicativo não requer hospedagem, banco, domínio ou API paga. GitHub público, Flutter, Android SDK, Linux e CI para repositórios públicos podem ser usados sem mensalidade. O custo operacional é tempo de manutenção e, opcionalmente, a taxa única exigida por uma loja caso o app seja publicado nela.

## Rotina mensal

1. Revise PRs do Dependabot e changelogs das dependências.
2. Execute `flutter pub outdated` e atualize em lotes pequenos.
3. Rode `flutter analyze`, `flutter test` e builds nas duas plataformas.
4. Teste dois dispositivos reais: descoberta, aceite, rejeição, arquivo vazio, arquivo grande, múltiplos arquivos, nome duplicado e rede interrompida.
5. Revise permissões e o diff de `pubspec.lock` antes do merge.

Não use `flutter pub upgrade --major-versions` sem revisar breaking changes e suporte mínimo de Android/Linux.

## Release

1. Atualize `version` em `pubspec.yaml` (`semver+build`).
2. Atualize `CHANGELOG.md`.
3. Garanta a branch limpa e CI verde.
4. Crie um commit `chore(release): prepare vX.Y.Z` e uma tag assinada `vX.Y.Z`.
5. Gere os binários de uma tag, calcule SHA-256 e publique checksums junto aos artefatos.

## Assinatura Android

Crie o keystore fora do repositório e guarde backup criptografado. Um `android/key.properties` local típico referencia o arquivo sem incluir a chave no Git:

```properties
storePassword=VALOR_LOCAL
keyPassword=VALOR_LOCAL
keyAlias=localbridge
storeFile=/caminho/fora/do/repositorio/localbridge.jks
```

O repositório ignora esses arquivos. Para distribuição pessoal durante o MVP, prefira o APK debug. Antes de uma release pública, configure `signingConfigs.release` no Gradle, armazene segredos somente no cofre do provedor de CI e nunca imprima valores em logs.

## Compatibilidade de protocolo

Mudanças apenas de UI não alteram o protocolo. Campos obrigatórios, rotas, semântica de status ou transporte exigem testes cruzados entre versões e possivelmente incremento de `protocolVersion`.

## Auditoria antes de push

```bash
git status --short
git diff --check
git diff -- . ':!package-lock.json' ':!pubspec.lock'
git grep -nEi '(api[_-]?key|secret|token|password|BEGIN .*PRIVATE KEY)'
```

Revise falsos positivos manualmente. Se um segredo já entrou no histórico, ignorá-lo depois não resolve: revogue-o e reescreva o histórico com coordenação explícita.
