const
  ZE*: uint32 = 1213550164'u32
  CompressFlag*: byte = 1'u8
  BatchFlag*: byte = 2'u8

proc xorCipher*(r: var openArray[byte], seed: uint32) =
  var t: uint32 = seed xor ZE
  if t == 0: t = ZE

  let alignedLen = r.len and (not 3)
  var a = 0
  while a < alignedLen:
    t = t xor (t shl 13)
    t = t xor (t shr 17)
    t = t xor (t shl 5)
    let b0 = uint32(r[a])
    let b1 = uint32(r[a + 1]) shl 8
    let b2 = uint32(r[a + 2]) shl 16
    let b3 = uint32(r[a + 3]) shl 24
    let val = b0 or b1 or b2 or b3
    let xored = val xor t
    r[a] = byte(xored and 0xFF)
    r[a + 1] = byte((xored shr 8) and 0xFF)
    r[a + 2] = byte((xored shr 16) and 0xFF)
    r[a + 3] = byte((xored shr 24) and 0xFF)
    a += 4

  if a < r.len:
    t = t xor (t shl 13)
    t = t xor (t shr 17)
    t = t xor (t shl 5)
    while a < r.len:
      let shift = (a and 3) * 8
      let mask = byte((t shr shift) and 0xFF)
      r[a] = r[a] xor mask
      a += 1
