# LocalBridge

Aplicativo Flutter gratuito e sem backend para transferir arquivos diretamente entre Android e Linux na mesma rede local.

Nenhuma conta, nuvem, mensalidade ou navegador é necessário. Abra o app nos dois dispositivos, escolha o destino e selecione os arquivos. No Linux também é possível arrastar arquivos para a janela; no Android, a LocalBridge aparece no menu **Compartilhar**.

> Estado: MVP funcional para uso pessoal. Mantenha o app aberto durante a transferência e use redes em que você confia.

## O que já funciona

- anúncio e descoberta automática Zeroconf/mDNS (`_localbridge._tcp`);
- conexão manual por `IP:porta` quando multicast estiver bloqueado;
- servidor e cliente HTTP simultâneos em Android e Linux;
- pedido de aceite antes de receber qualquer conteúdo;
- upload binário em stream, sem carregar arquivos grandes inteiros na RAM;
- múltiplos arquivos, progresso, validação de tamanho e SHA-256 opcional;
- nomes sanitizados, escrita temporária `.part` e proteção contra sobrescrita;
- seleção de pasta de recebimento;
- drag-and-drop no Linux e compartilhamento nativo no Android;
- tema claro/escuro, sem analytics, anúncios ou telemetria.

## Fluxo mais curto

1. Abra a LocalBridge no computador e no celular, conectados ao mesmo Wi-Fi.
2. No computador, arraste os arquivos para a janela; no Android, use **Compartilhar > LocalBridge**. Também é possível tocar no dispositivo e escolher arquivos.
3. Toque no dispositivo de destino.
4. Aceite no destino.

Os bytes trafegam diretamente entre os aparelhos. Internet não é necessária.

## Requisitos

- Flutter `3.44.8` ou outra versão estável compatível com Dart `>=3.12.2`;
- Git;
- Android Studio/Android SDK para Android;
- Ubuntu/Debian com os pacotes de compilação Flutter e Avahi para Linux.

Confira o ambiente:

```bash
flutter doctor -v
```

## Rodar no Linux

Em Ubuntu/Debian:

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev avahi-daemon
sudo systemctl enable --now avahi-daemon

flutter pub get
flutter run -d linux
```

Se o UFW bloquear conexões, libere apenas a porta TCP usada pelo app na rede local:

```bash
sudo ufw allow from 192.168.0.0/16 to any port 53317 proto tcp comment LocalBridge
```

Ajuste a sub-rede ao seu roteador. mDNS também depende de UDP `5353` e pode ser bloqueado em redes corporativas ou de convidados; nesse caso use **Conectar por IP**.

## Rodar no Android

1. Instale Android Studio e, pelo SDK Manager, o Android SDK e Platform Tools.
2. Ative depuração USB no aparelho e conecte-o.
3. Confirme o dispositivo e execute:

```bash
flutter devices
flutter pub get
flutter run -d ID_DO_DISPOSITIVO
```

Para gerar um APK pessoal instalável, sem publicar em loja:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Uma release pública precisa de assinatura própria. As chaves e `android/key.properties` são ignorados pelo Git e nunca devem ser commitados; veja [Manutenção](docs/MAINTENANCE.md).

## Verificações locais

```bash
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build linux --debug
```

## Arquitetura

Cada instância é um peer simétrico: anuncia e descobre dispositivos, hospeda um servidor HTTP local e inicia uploads quando necessário.

```text
Zeroconf/mDNS -> handshake de metadados -> aceite do usuário
             -> upload binário em stream -> validação -> arquivo final
```

O protocolo está em `lib/data/network`, os casos de uso e estado em `lib/application`, as entidades em `lib/domain` e a interface em `lib/presentation`. As camadas estão descritas em [ARCHITECTURE.md](docs/ARCHITECTURE.md), e o fluxo de rede e o modelo de confiança estão em [protocol.md](docs/protocol.md).

## Segurança e privacidade

- O app não possui servidor externo nem coleta dados.
- Transferências exigem aceite e só usam sessões temporárias autorizadas.
- O tráfego da LAN não é criptografado no MVP. Não use Wi-Fi público ou hostil.
- Nenhuma chave de assinatura, credencial ou arquivo recebido deve entrar no repositório.

Leia [SECURITY.md](SECURITY.md) e [PRIVACY.md](PRIVACY.md) antes de distribuir o aplicativo.

## Limitações conhecidas

- o app precisa permanecer aberto durante transferências;
- não há retomada de upload interrompido;
- isolamento entre clientes no roteador pode impedir descoberta e tráfego direto;
- descoberta foi projetada para Android e Linux; outras plataformas ainda não são alvo do projeto;
- HTTP na LAN é intencional no MVP e não oferece confidencialidade contra outros participantes da rede.

## Contribuição e manutenção

Contribuições seguem Conventional Commits e passam por format, analyze e test. Veja [CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md) e [docs/MAINTENANCE.md](docs/MAINTENANCE.md).

## Licença

MIT, consulte [LICENSE](LICENSE).
