import std/[asyncdispatch, httpclient, json, strutils]
import types

type
  SessionTicket* = object
    ticket*: string
    cookie*: string
    wsUrl*: string
    characterName*: string

proc loginAndGetTicket*(config: AccountConfig): Future[SessionTicket] {.async.} =
  let origin = if config.credentials.origin.len > 0: config.credentials.origin.strip(chars = {'/'}) else: "https://huntera.com.br"
  let email = config.credentials.email
  let password = config.credentials.password
  let charName = if config.credentials.characterName.len > 0: config.credentials.characterName else: config.name

  if email.len == 0 or password.len == 0:
    raise newException(IOError, "Credenciais vazias (email ou password)")

  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Origin": origin,
    "Referer": origin & "/",
    "Accept": "application/json, text/plain, */*",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
  })

  # 1. Login
  let loginUrl = origin & "/api/auth/login"
  let loginPayload = %*{"email": email, "password": password}
  let loginResp = await client.post(loginUrl, body = $loginPayload)
  let loginBody = await loginResp.body

  var sessionCookie = ""
  if loginResp.headers.hasKey("set-cookie"):
    let sc = loginResp.headers["set-cookie"]
    let idx = sc.find("tw_session=")
    if idx >= 0:
      let endIdx = sc.find(';', idx)
      sessionCookie = if endIdx >= 0: sc[idx ..< endIdx] else: sc[idx..^1]

  if sessionCookie.len == 0:
    client.close()
    raise newException(IOError, "Login falhou: sem cookie tw_session (" & loginResp.status & ") - " & loginBody)

  # 2. Get characters
  let charsUrl = origin & "/api/characters"
  client.headers["Cookie"] = sessionCookie
  let charsResp = await client.get(charsUrl)
  let charsBody = await charsResp.body
  let charsJson = parseJson(charsBody)

  var charId = ""
  var charsArr = if charsJson.kind == JArray: charsJson
                 elif charsJson.hasKey("characters") and charsJson["characters"].kind == JArray: charsJson["characters"]
                 else: newJArray()

  for c in charsArr:
    let n = c{"name"}.getStr()
    if cmpIgnoreCase(n, charName) == 0:
      if c.hasKey("id"):
        charId = if c["id"].kind == JInt: $c["id"].getInt() else: c["id"].getStr()
      break

  if charId.len == 0 and charsArr.len > 0:
    let first = charsArr[0]
    if first.hasKey("id"):
      charId = if first["id"].kind == JInt: $first["id"].getInt() else: first["id"].getStr()

  if charId.len == 0:
    client.close()
    raise newException(IOError, "Personagem '" & charName & "' não encontrado em /api/characters")

  # 3. Game tickets
  let ticketUrl = origin & "/api/game-tickets"
  let ticketPayload = %*{"characterId": charId}
  let ticketResp = await client.post(ticketUrl, body = $ticketPayload)
  let ticketBody = await ticketResp.body
  client.close()

  let ticketJson = parseJson(ticketBody)
  let ticket = ticketJson{"ticket"}.getStr()
  if ticket.len == 0:
    raise newException(IOError, "Campo 'ticket' não encontrado na resposta de game-tickets: " & ticketBody)

  let wsUrl = ticketJson{"websocketUrl"}.getStr("wss://huntera.com.br/game-socket")

  result = SessionTicket(
    ticket: ticket,
    cookie: sessionCookie,
    wsUrl: wsUrl,
    characterName: charName
  )
