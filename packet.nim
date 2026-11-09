import std/[json, tables, random, strutils]
import zippy
import cipher

const
  ClientVersion* = "0.3.0+e0"
  OpcodesRaw = staticRead("opcodes.json")

var
  outgoingCodes: Table[string, int]
  incomingNames: Table[int, string]
  opcodesInitialized = false

proc initOpcodes() =
  if opcodesInitialized: return
  outgoingCodes = initTable[string, int]()
  incomingNames = initTable[int, string]()
  try:
    let node = parseJson(OpcodesRaw)
    if node.hasKey("outgoing"):
      for k, v in node["outgoing"]:
        outgoingCodes[k] = v.getInt()
    if node.hasKey("incoming"):
      for k, v in node["incoming"]:
        let code = v.getInt()
        incomingNames[code] = k
  except CatchableError as e:
    echo "[Packet] Erro ao carregar opcodes.json: ", e.msg
  opcodesInitialized = true

initOpcodes()

proc outgoingCode*(msgType: string): int =
  if not opcodesInitialized: initOpcodes()
  if outgoingCodes.hasKey(msgType):
    return outgoingCodes[msgType]
  return -1

proc incomingName*(code: int): string =
  if not opcodesInitialized: initOpcodes()
  if incomingNames.hasKey(code):
    return incomingNames[code]
  return "unknown"

proc encodePacket*(msgType: string, payload: JsonNode, explicitSeed: uint32 = 0): seq[byte] =
  let code = outgoingCode(msgType)
  if code < 0:
    echo "[Packet] Ação desconhecida: ", msgType
    return @[]

  let arr = %*[newJInt(code), payload]
  var jsonStr = $arr
  var flags: byte = 0

  if jsonStr.len >= 8192:
    try:
      let compressed = compress(jsonStr, dataFormat = dfDeflate)
      jsonStr = compressed
      flags = flags or CompressFlag
    except CatchableError:
      discard

  var seed = explicitSeed
  if seed == 0:
    seed = (uint32(rand(0xFFFF)) shl 16) or uint32(rand(0xFFFF))
    if seed == 0: seed = 12345678

  var outBuf = newSeq[byte](5 + jsonStr.len)
  outBuf[0] = byte(seed and 0xFF)
  outBuf[1] = byte((seed shr 8) and 0xFF)
  outBuf[2] = byte((seed shr 16) and 0xFF)
  outBuf[3] = byte((seed shr 24) and 0xFF)
  outBuf[4] = flags

  for i in 0 ..< jsonStr.len:
    outBuf[5 + i] = byte(ord(jsonStr[i]))

  var bodySlice = outBuf[4..^1]
  xorCipher(bodySlice, seed)
  for i in 0 ..< bodySlice.len:
    outBuf[4 + i] = bodySlice[i]

  result = outBuf

proc decodeSingle(content: seq[byte], flags: byte): (string, JsonNode) =
  var rawStr = newString(content.len)
  for i in 0 ..< content.len:
    rawStr[i] = chr(content[i])

  if (flags and CompressFlag) != 0:
    try:
      rawStr = uncompress(rawStr, dataFormat = dfDeflate)
    except CatchableError:
      return ("", newJNull())

  try:
    let node = parseJson(rawStr)
    if node.kind == JArray and node.len >= 2:
      let code = node[0].getInt()
      let name = incomingName(code)
      let payload = node[1]
      return (name, payload)
  except CatchableError:
    discard
  return ("", newJNull())

proc decodeFrame*(raw: seq[byte]): seq[(string, JsonNode)] =
  if raw.len < 5: return @[]

  let b0 = uint32(raw[0])
  let b1 = uint32(raw[1]) shl 8
  let b2 = uint32(raw[2]) shl 16
  let b3 = uint32(raw[3]) shl 24
  let seed = b0 or b1 or b2 or b3

  var body = raw[4..^1]
  xorCipher(body, seed)
  if body.len == 0: return @[]

  let flags = body[0]
  let content = body[1..^1]

  if (flags and BatchFlag) == 0:
    let (name, payload) = decodeSingle(content, flags)
    if name.len > 0:
      return @[(name, payload)]
    return @[]

  # Batch frames
  var offset = 0
  var events: seq[(string, JsonNode)] = @[]
  while offset + 4 <= content.len:
    let l0 = int(content[offset])
    let l1 = int(content[offset + 1]) shl 8
    let l2 = int(content[offset + 2]) shl 16
    let l3 = int(content[offset + 3]) shl 24
    let length = l0 or l1 or l2 or l3
    offset += 4
    if length <= 0 or offset + length > content.len: break
    let subContent = content[offset ..< offset + length]
    let (name, payload) = decodeSingle(subContent, flags)
    if name.len > 0:
      events.add((name, payload))
    offset += length

  result = events
