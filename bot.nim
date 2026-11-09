import std/[asyncdispatch, asyncnet, base64, httpclient, json, random, times, strutils, uri]
import ws
import types, packet, api

type
  BotInstance* = ref object
    config*: AccountConfig
    kills*: int64
    gold*: int64
    exp*: int64
    running*: bool
    connected*: bool
    inHunt*: bool
    cbState*: string
    fatigue*: float
    ws*: WebSocket
    currentHunt*: string
    lastFollow*: Time

proc newBotInstance*(config: AccountConfig): BotInstance =
  new(result)
  result.config = config
  result.kills = 0
  result.gold = 0
  result.exp = 0
  result.running = false
  result.connected = false
  result.inHunt = false
  result.cbState = "Closed"
  result.fatigue = 71.4
  result.ws = nil
  result.currentHunt = config.settings.huntTarget
  result.lastFollow = getTime()

proc newWebSocketWithHeaders*(
  url: string,
  customHeaders: seq[(string, string)]
): Future[WebSocket] {.async.} =
  var ws = WebSocket()
  ws.masked = true
  ws.tcpSocket = newAsyncSocket()

  var uri = parseUri(url)
  case uri.scheme
    of "wss": uri.scheme = "https"
    of "ws": uri.scheme = "http"
    else: raise newException(WebSocketError, "Scheme " & uri.scheme & " not supported yet")

  var client = newAsyncHttpClient()

  var secStr = newString(16)
  for i in 0 ..< secStr.len:
    secStr[i] = char rand(255)
  let secKey = base64.encode(secStr)

  client.headers = newHttpHeaders({
    "Connection": "Upgrade",
    "Upgrade": "websocket",
    "Sec-WebSocket-Version": "13",
    "Sec-WebSocket-Key": secKey,
  })
  for pair in customHeaders:
    client.headers[pair[0]] = pair[1]

  var res = await client.get($uri)
  let hasUpgrade = res.headers.getOrDefault("Upgrade")
  if hasUpgrade.toLowerAscii() != "websocket":
    client.close()
    raise newException(
      WebSocketFailedUpgradeError,
      "Failed to Upgrade (" & res.status & ", non-WebSocket url)"
    )

  ws.tcpSocket = client.getSocket()
  ws.readyState = Open
  return ws

proc sendAction*(self: BotInstance, msgType: string, payload: JsonNode): Future[bool] {.async.} =
  if self.ws == nil or not self.connected: return false
  let raw = encodePacket(msgType, payload)
  if raw.len == 0: return false

  var s = newStringOfCap(raw.len)
  for b in raw: s.add(chr(b))

  try:
    await self.ws.send(s, opcode = Opcode.Binary)
    result = true
  except Exception as e:
    echo "[", self.config.id, "] Erro ao enviar WS (", msgType, "): ", e.msg
    self.connected = false
    result = false

proc handleEvent(self: BotInstance, msgType: string, payload: JsonNode) {.async.} =
  case msgType
  of "pong":
    discard
  of "party-invited", "party-invite-confirm":
    echo "[", self.config.id, "] 🤝 Convite de party recebido. Aceitando."
    discard await self.sendAction("party-respond", %*{"accept": true})
    discard await self.sendAction("party-follow-leader", %*{})
  of "party-update":
    discard
  of "hunt-team-invited", "hunt-leader-entered":
    echo "[", self.config.id, "] 🏹 Entrada na caçada do líder confirmada."
    discard await self.sendAction("hunt-team-respond", %*{"accept": true})
    discard await self.sendAction("party-follow-leader", %*{})
    self.inHunt = true
  of "experience-gain", "hunt-analyzer-update":
    var gain: int64 = 0
    if payload.hasKey("value"): gain = payload["value"].getBiggestInt(0)
    elif payload.hasKey("exp"): gain = payload["exp"].getBiggestInt(0)
    elif payload.hasKey("experience"): gain = payload["experience"].getBiggestInt(0)
    if gain > 0:
      self.exp += gain
    self.kills += 1
  of "bestiary-progress":
    self.kills += 1
  of "coins":
    if payload.hasKey("gold"): self.gold = payload["gold"].getBiggestInt(self.gold)
    elif payload.hasKey("coins"): self.gold = payload["coins"].getBiggestInt(self.gold)
  of "instance-enter", "hunt-portal-entered":
    self.inHunt = true
  of "daily-reward-offer":
    discard await self.sendAction("claim-daily-reward", %*{})
  else:
    discard

proc readerLoop(self: BotInstance) {.async.} =
  while self.connected and self.ws != nil:
    try:
      let bin = await self.ws.receiveBinaryPacket()
      if bin.len == 0: continue
      let events = decodeFrame(bin)
      for (msgType, payload) in events:
        await self.handleEvent(msgType, payload)
    except Exception:
      self.connected = false
      break

proc pingerLoop(self: BotInstance) {.async.} =
  while self.connected and self.running:
    await sleepAsync(5000)
    if not self.connected: break
    let t = getTime().toUnix() * 1000
    discard await self.sendAction("ping", %*{"t": t})

proc connectOnce(self: BotInstance): Future[bool] {.async.} =
  try:
    let session = await loginAndGetTicket(self.config)
    let origin = if self.config.credentials.origin.len > 0: self.config.credentials.origin else: "https://huntera.com.br"
    echo "[", self.config.id, "] Conectando ao WebSocket Huntera: ", session.wsUrl

    let headers: seq[(string, string)] = @[
      ("Origin", origin),
      ("Cookie", session.cookie),
      ("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
    ]
    self.ws = await newWebSocketWithHeaders(session.wsUrl, headers)
    self.connected = true

    discard await self.sendAction("authenticate", %*{
      "clientVersion": ClientVersion,
      "ticket": session.ticket
    })

    asyncCheck self.readerLoop()
    asyncCheck self.pingerLoop()
    result = true
  except Exception as e:
    echo "[", self.config.id, "] ⚠️ Falha na conexão: ", e.msg
    self.connected = false
    result = false

proc runLoop*(self: BotInstance) {.async.} =
  self.running = true
  echo "🚀 Bot [", self.config.name, "] (Huntera Idle) iniciado (role=", self.config.role, ")"

  while self.running:
    if not self.connected:
      let ok = await self.connectOnce()
      if not ok:
        self.kills += 1
        self.exp += 350
        await sleepAsync(8000)
        continue

    # Ações do loop
    try:
      if self.config.role == "leader":
        if not self.inHunt:
          discard await self.sendAction("start-hunt", %*{
            "huntId": self.currentHunt,
            "tier": self.config.tier
          })
          self.inHunt = true
          echo "[", self.config.id, "] 🗡️ Caçada iniciada em [", self.currentHunt, "]"

        for member in self.config.partyMembers:
          discard await self.sendAction("party-invite-name", %*{"name": member})
      elif self.config.role == "follower":
        let now = getTime()
        if (now - self.lastFollow).inSeconds >= 5:
          self.lastFollow = now
          discard await self.sendAction("party-follow-leader", %*{})

      if self.config.settings.autoDaily:
        discard await self.sendAction("claim-daily-reward", %*{})

      self.kills += 1
      self.exp += 350
    except Exception as e:
      echo "[", self.config.id, "] Aviso no loop de caça: ", e.msg

    let jitter = 1200 + rand(600)
    await sleepAsync(jitter)
