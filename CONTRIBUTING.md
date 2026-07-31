# Contribuindo

1. Abra uma issue descrevendo mudanças grandes ou incompatíveis de protocolo.
2. Crie uma branch curta a partir de `main`.
3. Não inclua arquivos recebidos, credenciais, chaves ou dados pessoais em fixtures.
4. Adicione testes proporcionais ao risco.
5. Execute:

```bash
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

Commits usam [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat(discovery): add IPv6 peer fallback
fix(transfer): reject oversized stream
docs: explain Android signing
test(server): cover expired sessions
```

Tipos aceitos: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore` e `revert`. Mudanças incompatíveis precisam de `!` ou rodapé `BREAKING CHANGE:` e incremento da versão do protocolo quando afetarem interoperabilidade.

Pull requests devem explicar problema, solução, testes executados e impacto em Android/Linux. Mudanças de dependências precisam justificar manutenção, licença e permissões adicionais.
