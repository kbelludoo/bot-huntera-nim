import std/[asyncdispatch, json, os, strutils]
import types, bot, dashboard

const DefaultAccountsExample = staticRead("accounts.example.json")

proc formatNumber(n: int64): string =
  if n < 1000:
    $n
  elif n < 1000000:
    formatFloat(n.float / 1000.0, ffDecimal, 1) & "k"
  else:
    formatFloat(n.float / 1000000.0, ffDecimal, 2) & "kk"

proc tickerLoop(bots: seq[BotInstance]) {.async.} =
  var tick: int64 = 0
  while true:
    await sleepAsync(4000)
    tick += 1

    var totalKills: int64 = 0
    var totalGold: int64 = 0
    var totalExp: int64 = 0

    for b in bots:
      totalKills += b.kills
      totalGold += b.gold
      totalExp += b.exp

    echo "[Console Ticker #", tick, "] Contas: ", bots.len, " | Kills: ", totalKills, " | Gold: ", totalGold, " | Exp: ", formatNumber(totalExp)

proc main() {.async.} =
  echo "================================================================================"
  echo "       ⚡ HUNTERA NATIVE NIM BOT (ARC/ORC ZERO-GC & ALTA PERFORMANCE) ⚡"
  echo "================================================================================"

  let configPath = "accounts.json"
  var content = ""
  if fileExists(configPath):
    content = readFile(configPath)
  else:
    echo "⚠️ Arquivo accounts.json não encontrado. Criando template padrão..."
    writeFile(configPath, DefaultAccountsExample)
    content = DefaultAccountsExample

  let allNodes = parseJson(content)
  var activeConfigs: seq[AccountConfig] = @[]
  let targetAcc = getEnv("ACCOUNT", "")

  for node in allNodes:
    let cfg = parseAccountConfig(node)
    if not cfg.enabled and cfg.id != targetAcc:
      continue
    if targetAcc.len > 0 and cfg.id != targetAcc:
      continue
    activeConfigs.add(cfg)

  if activeConfigs.len == 0:
    echo "⚠️ Nenhuma conta com 'enabled: true' encontrada em accounts.json."

  var bots: seq[BotInstance] = @[]
  for cfg in activeConfigs:
    let b = newBotInstance(cfg)
    bots.add(b)
    asyncCheck b.runLoop()

  let portStr = getEnv("PORT", "3000")
  var port = 3000
  try:
    port = parseInt(portStr)
  except ValueError:
    port = 3000

  let server = newDashboardServer(port, bots)
  asyncCheck server.start()
  asyncCheck tickerLoop(bots)

  echo "Bot operacional na porta ", port, ". Pressione Ctrl+C para encerrar."
  runForever()

waitFor main()
