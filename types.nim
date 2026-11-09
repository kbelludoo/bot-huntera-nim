import std/[json, strutils]

type
  GameCredentials* = object
    token*: string
    email*: string
    password*: string
    origin*: string
    characterName*: string

  GameSettings* = object
    huntTarget*: string
    autoHunt*: bool
    autoSell*: bool
    autoHeal*: bool
    autoDaily*: bool
    autoTreino*: bool
    bindIp*: string

  AccountConfig* = object
    id*: string
    name*: string
    enabled*: bool
    role*: string            # "leader" | "follower" | "solo"
    partyMembers*: seq[string]
    partnerName*: string
    tier*: int
    credentials*: GameCredentials
    settings*: GameSettings

proc defaultSettings*(): GameSettings =
  result = GameSettings(
    huntTarget: "cult-hunt",
    autoHunt: true,
    autoSell: true,
    autoHeal: true,
    autoDaily: true,
    autoTreino: true,
    bindIp: ""
  )

proc parseAccountConfig*(node: JsonNode): AccountConfig =
  result.id = node{"id"}.getStr()
  result.name = node{"name"}.getStr()
  result.enabled = node{"enabled"}.getBool(true)
  result.role = node{"role"}.getStr("solo")
  result.partnerName = node{"partnerName"}.getStr()
  result.tier = node{"tier"}.getInt(0)

  result.partyMembers = @[]
  if result.partnerName.len > 0:
    for m in result.partnerName.split(','):
      let trimmed = m.strip()
      if trimmed.len > 0: result.partyMembers.add(trimmed)
  elif node.hasKey("partyMembers"):
    for m in node["partyMembers"]:
      result.partyMembers.add(m.getStr())

  result.settings = defaultSettings()
  result.credentials.origin = "https://huntera.com.br"

  # Flat fields compatibility
  if node.hasKey("email"): result.credentials.email = node["email"].getStr()
  if node.hasKey("password"): result.credentials.password = node["password"].getStr()
  if node.hasKey("token"): result.credentials.token = node["token"].getStr()
  if node.hasKey("characterName"): result.credentials.characterName = node["characterName"].getStr()
  if node.hasKey("origin"): result.credentials.origin = node["origin"].getStr("https://huntera.com.br")
  if node.hasKey("huntId"): result.settings.huntTarget = node["huntId"].getStr()

  # Structured credentials if present
  if node.hasKey("credentials"):
    let c = node["credentials"]
    if c.hasKey("email"): result.credentials.email = c["email"].getStr()
    if c.hasKey("password"): result.credentials.password = c["password"].getStr()
    if c.hasKey("token"): result.credentials.token = c["token"].getStr()
    if c.hasKey("character_name"): result.credentials.characterName = c["character_name"].getStr()
    elif c.hasKey("characterName"): result.credentials.characterName = c["characterName"].getStr()
    if c.hasKey("origin"): result.credentials.origin = c["origin"].getStr("https://huntera.com.br")

  # Structured settings if present
  if node.hasKey("settings"):
    let s = node["settings"]
    if s.hasKey("hunt_target"): result.settings.huntTarget = s["hunt_target"].getStr()
    elif s.hasKey("huntTarget"): result.settings.huntTarget = s["huntTarget"].getStr()
    if s.hasKey("auto_hunt"): result.settings.autoHunt = s["auto_hunt"].getBool(true)
    elif s.hasKey("autoHunt"): result.settings.autoHunt = s["autoHunt"].getBool(true)
    if s.hasKey("auto_daily"): result.settings.autoDaily = s["auto_daily"].getBool(true)
    elif s.hasKey("autoDaily"): result.settings.autoDaily = s["autoDaily"].getBool(true)

  if result.credentials.characterName.len == 0:
    result.credentials.characterName = result.name
