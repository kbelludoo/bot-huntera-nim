import std/[asyncdispatch, asynchttpserver, json, times, strutils]
import bot

type
  DashboardServer* = ref object
    port*: int
    startTime*: Time
    bots*: seq[BotInstance]
    server*: AsyncHttpServer

proc newDashboardServer*(port: int, bots: seq[BotInstance]): DashboardServer =
  new(result)
  result.port = port
  result.startTime = getTime()
  result.bots = bots
  result.server = newAsyncHttpServer()

proc handleRequest(self: DashboardServer, req: Request) {.async.} =
  var headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  })

  if req.reqMethod == HttpOptions:
    await req.respond(Http200, "{}", headers)
    return

  let path = req.url.path

  if req.reqMethod == HttpGet and path == "/api/status":
    var accountsArr = newJArray()
    for b in self.bots:
      accountsArr.add(%*{
        "id": b.config.id,
        "name": b.config.name,
        "running": b.running,
        "kills": b.kills,
        "gold": b.gold,
        "exp": b.exp,
        "cb_state": b.cbState,
        "fatigue": b.fatigue
      })

    let uptime = (getTime() - self.startTime).inSeconds
    let responseObj = %*{
      "game": "Huntera Idle",
      "engine": "Native Nim ARC/ORC",
      "uptime_sec": uptime,
      "total_accounts": self.bots.len,
      "port": self.port,
      "accounts": accountsArr
    }
    await req.respond(Http200, $responseObj, headers)
    return

  if req.reqMethod == HttpPost and path == "/api/ticket":
    try:
      let bodyNode = parseJson(req.body)
      let t = if bodyNode.hasKey("token"): bodyNode["token"].getStr()
              elif bodyNode.hasKey("ticket"): bodyNode["ticket"].getStr()
              else: ""
      if t.len > 0:
        await req.respond(Http200, $(%*{"ok": true, "message": "Ticket registrado com sucesso"}), headers)
        return
    except CatchableError:
      discard
    await req.respond(Http400, $(%*{"ok": false, "error": "Token ausente"}), headers)
    return

  await req.respond(Http404, $(%*{"error": "Not Found"}), headers)

proc start*(self: DashboardServer) {.async.} =
  echo "🌐 Servidor HTTP dashboard iniciado em http://0.0.0.0:", self.port
  let server = self.server
  let sSelf = self
  await server.serve(Port(self.port), proc(req: Request): Future[void] =
    sSelf.handleRequest(req)
  )
