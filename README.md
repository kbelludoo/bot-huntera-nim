# ⚡ Bot Huntera Idle — Native Nim Engine (ARC/ORC)

Multi-account automation engine for **Huntera Idle** rewritten in native **Nim 2.2** with zero-overhead memory management (`--mm:orc`), asynchronous WebSocket, custom XORShift cipher, and complete parity with Go and Rust implementations.

---

## 🚀 Características & Paridade 100%

- **Protocolo Binário Huntera**: Enquadramento `[seed: u32 LE][flags: u8][payload]` com cifra XORShift (`ZE = 1213550164`), compressão Deflate via `zippy` e decodificação JSON de opcodes.
- **Party Coordinator**: Suporte a time cooperativo de 4 vocações (Leader convida e inicia caçadas, Followers aceitam convites e seguem líder automaticamente).
- **REST Session Ticket**: Autenticação REST em `/api/auth/login`, listagem de personagens em `/api/characters`, e emissão de ticket em `/api/game-tickets`.
- **Pacing Orgânico Anti-Detecção**: Jitter gaussiano contínuo (1.2s - 1.8s) sem paradas offline forçadas.
- **Dashboard Telemetria HTTP (Porta 3000)**: Status JSON em `/api/status`, injeção de tickets em `/api/ticket`.

---

## 🛠️ Compilação Cruzada (Cross-Compilation via Zig)

```bash
nim c --os:linux --cpu:amd64 --gcc.exe:zigcc-linux-gnu.bat --gcc.linkerexe:zigcc-linux-gnu.bat -d:ssl -d:release -o:bot-huntera-linux-nim main.nim
```

---

## ⚙️ Configuração

Copie o arquivo `accounts.example.json` para `accounts.json` e configure suas credenciais:

```bash
cp accounts.example.json accounts.json
```
