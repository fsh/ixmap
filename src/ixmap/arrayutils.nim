import std/macros


proc rollRight*[I, T](arr: var array[I, T], r: Slice[int]) {.inline.} =
  if r.a < r.b:
    let tmp = arr[r.b]
    for i in countdown(r.b, r.a+1):
      arr[i] = arr[i-1]
    arr[r.a] = tmp

proc rollLeft*[I, T](arr: var array[I, T], r: Slice[int]) {.inline.} =
  if r.a < r.b:
    let tmp = arr[r.a]
    for i in countup(r.a, r.b-1):
      arr[i] = arr[i+1]
    arr[r.b] = tmp

proc `&`*[N, M: static[int]; T](a: array[N, T], b: array[M, T]): auto {.inline.} =
  const D = N + M
  var res: array[D, T]
  res[0 ..< N] = a
  res[N ..< D] = b
  res

proc remove*[N: static[int], T](arr: array[N, T], idx: int): auto {.inline.} =
  var res: array[N - 1, T]
  for i in 0 ..< idx:
    res[i] = arr[i]
  for i in idx ..< N-1:
    res[i] = arr[i+1]
  res

proc insert*[N: static[int], T](arr: array[N, T], idx: int, val: sink T): auto {.inline.} =
  var res: array[N + 1, T]
  for i in 0 ..< idx:
    res[i] = arr[i]
  res[idx] = val
  for i in idx ..< N:
    res[i+1] = arr[i]
  res


template binop_impl(op, r, x, y, n: untyped): untyped =
  r = x
  for i in 0 ..< n:
    r[i] = op(r[i], y[i])

template aligned_op(short, long, op: untyped): untyped =
  func long*[N, M: static[int], T](a: array[N, T], b: array[M, T]): auto {.inline.} =
    when N < M:
      binop_impl(op, result, b, a, N)
    else:
      binop_impl(op, result, a, b, M)

  func short*[N, M: static[int], T](a: array[N, T], b: array[M, T]): auto {.inline.} =
    when N < M:
      binop_impl(op, result, a, b, N)
    else:
      binop_impl(op, result, b, a, M)

aligned_op(shortMax, longMax, max)
aligned_op(shortMin, longMin, min)

macro shortDotProduct*[N, M: static[int]; T, U, R](initial: R, x: array[N, T], y: array[M, U]): untyped =
  ## Macro for the expression `initial + x[0] * y[0] + x[1] * y[1] + ...` up to
  ## the length of the shortest array given.
  let L = min(N, M)
  let Ty = genSym(nskType, "U")
  result = initial
  for i in 0 ..< L:
    result = quote:
      `result` + `Ty`(`x`[`i`]) * `Ty`(`y`[`i`])
  result = quote:
    block:
      type `Ty` = typeof(`initial`)
      `result`
