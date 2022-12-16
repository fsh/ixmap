
import std/[algorithm, genasts, strformat]
import std/macros as stdmacros

from pkg/strides import AnyStrided

import types

template qq*(q: untyped): untyped = quote:
  q

macro foldArgsR*(op: untyped, initial: untyped, args: varargs[untyped]): untyped =
  ## Folds over a variable number of arguments, potentially with different types.
  ##
  ## This particular fold is right associative, meaning it starts at the end and
  ## the first argument gets evaluated last:
  ##
  ## `foldArgsR(x, f, [1,2,3])` is equivalent to `f(1, f(1, f(2, f(3, x))))`.
  ##
  result = initial
  for expr in args[0 .. ^1].reversed():
    result = newCall(op, expr, result)



macro constrCopy*(axes: static[set[Axis]]; dest, src: untyped): untyped =
  result = newStmtList()
  for (ti, si) in pairs(axes):
    result.add:
      quote:
        `dest`[`ti`] = `src`[`si`]

macro constrLoopTower*[N, M: static[int], T, U](coords: array[N, T], shape: array[M, U]; body: untyped): untyped =
  assert N <= M
  result = body
  for i in 0 ..< N:
    let li = N - 1 - i
    result = quote:
      `coords`[`li`] = 0
      while `coords`[`li`] < `shape`[`li`]:
        `result`
        `coords`[`li`].inc


macro constrOffset*[D, L: static[int]; T, U](axes: static[set[Axis]]; initial: int, stride: array[D, T], coords: array[L, U]): untyped =
  let axes = Axis(D).filter(axes)
  assert len(axes) <= L, "axes exceeds loop indices"
  result = initial
  for (li, si) in pairs(axes):
    result = quote:
      `result` + int(`coords`[`li`]) * int(`stride`[`si`])

macro constrStrideSort*(dims: static[int], primary: array, arrays: varargs[array]): untyped =
  ## Produces code for sorting the array `primary`, which also permutes the
  ## additional arrays given in the same way.
  result = newStmtList()
  for i in Axis.low.succ .. dims.pred:
    for j in countdown(i.pred, Axis.low):
      var extra_swaps = newStmtList()
      for extra in arrays:
         extra_swaps.add(qq(swap(`extra`[`j`], `extra`[`j`.succ])))
      result.add:
        quote:
          if `primary`[`j`] < `primary`[`j`.succ]:
            swap(`primary`[`j`], `primary`[`j`.succ])
            `extra_swaps`



# [2,3,4] :: [2,3,4,7,2]

# macro constrStaticMultiLoop*(offsets: untyped; primary: untyped; src1: untyped; body: untyped): untyped =
#   # let loopidx = genSym(nskVar, "loopidx")

#   # # constrOffset(AllAxes, qq(`primary`.offset), qq(`primary`.stride), loopidx)
#   # let yy = getAst(AllAxes, constrOffset(qq(`primary`.offset), qq(`primary`.stride), loopidx))
#   # echo "result = ", yy.treeRepr()

#   quote:
#     echo "ok"

  # let axes = AllAxes
  # var arrvalue = nnkBracketExpr.newTree()
  # arrvalue.add(getAst(constrOffset(qq(`primary`.offset), axes, qq(`primary`.stride), loopidx)))

  # arrvalue.add(getAst(constrOffset(qq(`src1`.offset), axes, qq(`src1`.stride), loopidx)))
  # # for src in sources:
  # #   arrvalue.add(getAst(constrOffset(qq(`src`.offset), axes, qq(`src`.stride), loopidx)))

  # echo "arrvalue = ", arrvalue.treeRepr()

  # let body = quote:
  #   let `offsets` = `arrvalue`
  #   `body`

  # let loop_tower = getAst(
  #   constrLoops(axes.toSeq, loopidx, qq(`primary`.shape), body))

  # let loop_dims = qq(`primary`.shape.len)
  # result = quote:
  #   var `loopidx`: IxArray[`loop_dims`]
  #   `loop_tower`


  # echo "RESULT ==> ", result.treeRepr()

#   var preamble = newStmtList:
#     var `loopidx`: IxArray[`loop_dims`]

#   var
#     si = 0
#     ti = 0
#     li = 0
#   while si < dims:
#     if si in axes:
#       # This ought to be hoisted and strength-reduced by C optimizer.
#       offset_expr = quote: `offset_expr` + `li` * `src`.stride[`si`]
#       shapeidx.add(si)
#       li.inc
#     else:
#       # This axis goes in the output.
#       preamble.add:
#         quote:
#           `target`.shape[`ti.newLit`] = `src`.shape[`si`]
#           `target`.stride[`ti.newLit`] = `src`.stride[`si`]
#       ti.inc
#     si.inc

#   assert axes.len == li

#   var loops = quote:
#     `target`.offset = `offset_expr`
#     `body`

#   for lidx in countdown(axes.len() - 1, 0):
#     let si = shapeidx[lidx]
#     loops = quote:
#       `loopidx`[`lidx`] = 0
#       while `loopidx`[`lidx`] < `src`.shape[`si`]:
#         `loops`
#         `loopidx`[`lidx`].inc

#   quote:
#     `preamble`
#     `loops`

type IndexVars = tuple[what: NimNode, srcidx: NimNode, destidx: NimNode]

func constSym(s: string): NimNode = genSym(nskConst, s)

func initVars(code: NimNode, vars: var seq[IndexVars]) =
  let
    srcidx = constSym("srcfirst")
    destidx = constSym("destfirst")
  vars.add( (nil, srcidx, destidx) )
  code.add:
    genAst(srcidx, destidx):
      const
        srcidx = -1
        destidx = -1

func processIndex(code: NimNode, vars: var seq[IndexVars], expr: NimNode) =
  let
    what = constSym("what")
    srcidx = constSym("srcidx")
    destidx = constSym("destidx")
    srcprev = vars[^1].srcidx
    destprev = vars[^1].destidx

  let ast = if eqIdent(expr, "_"):
    genAst(what, srcidx, destidx, srcprev, destprev):
      const
        what = 'k'
        srcidx = srcprev + 1
        destidx = destprev + 1
  else:
    genAst(expr, what, srcidx, destidx, srcprev, destprev):
      type T = typeof(expr, typeOfProc)
      when T is (SomeInteger | BackwardsIndex):
        const
          what = 'c'
          srcidx = srcprev + 1
          destidx = destprev
      elif T is NewAxis:
        const
          what = 'n'
          srcidx = srcprev
          destidx = destprev + 1
      elif T is (HSlice | AnyStrided):
        const
          what = 's'
          srcidx = srcprev + 1
          destidx = destprev + 1
      else:
        {. error "invalid type used in [] index" .}

  code.add(ast)
  vars.add((what, srcidx, destidx))







func reverseIndex(code: NimNode, idx: NimNode, tot: NimNode | int): NimNode =
  result = constSym($idx & "R")
  code.add:
    quote:
      const `result` = `tot` - `idx` - 1

func etcScan(xs: var seq[NimNode], inp: NimNode, i: int): int =
  result = i
  while result < inp.len():
    let e = inp[result]
    if eqIdent(e, "etc"):
      break
    xs.add(if eqIdent(e, "new"): newCall("rep", newLit(1)) else: e)
    result.inc


template indexExpand[D: static[int]](src: IxMap[D], ix: int) =
  let next = collapse(prev, d, ix)
  const nextd = d + 1




proc constrBracketIndex*(dims: int, srcexpr: NimNode, ixlist: NimNode): NimNode =
  var etc_found = false
  var d = -1

  var stack = newSeqOfCap[(int,NimNode)](ixlist.len)
  for ixnode in children(ixlist):
    d.inc
    assert d >= 0 and d < dims, "dimension index out of bounds"

    if eqIdent(ixnode, "_"):
      continue

    if eqIdent(ixnode, "etc"):
      doAssert not etc_found, "etc used more than once in indexing"
      etc_found = true
      d += dims - ixlist.len
      continue

    stack.add( (d, ixnode) )

  result = srcexpr
  for (d, e) in stack.reversed():
    result = newCall(ident("select"), result, newLit(d), e)




proc constrIndexing*(D: static[int], srcexpr: NimNode, ixs: NimNode): NimNode =
  result = newStmtList()
  var forward = newSeqOfCap[NimNode](ixs.len())
  var backward = newSeqOfCap[NimNode](ixs.len())
  let etc = forward.etcScan(ixs, 0)
  assert etc == forward.len()
  if etc < ixs.len():
    # 'etc' token found.
    let totix = backward.etcScan(ixs, etc + 1)
    assert totix == ixs.len(), "can't have more than two `etc` terms in [] index"
    backward.reverse()

  var vars: seq[IndexVars]

  result.initVars(vars)
  for e in forward:
    result.processIndex(vars, e)

  assert vars.len == etc + 1

  result.initVars(vars)
  for e in backward:
    result.processIndex(vars, e)

  # All indices processed, now we can calculate the actual resulting dimension.
  let
    desttotal = constSym("desttotal")
    etctotal = constSym("etctotal")
  result.add:
    genAst(D, desttotal, etctotal,
           srcfwd=vars[etc].srcidx, srcrev=vars[^1].srcidx,
           destfwd=vars[etc].destidx, destrev=vars[^1].destidx):
      const etctotal = D - (srcfwd + 1) - (srcrev + 1)
      static:
        assert etctotal >= 0, "too many indices given"
      const desttotal = (destfwd + 1) + (destrev + 1) + etctotal

  # Modify the post-etc indices to refer to the ending.
  for i in etc+1 ..< vars.len:
    vars[i].srcidx = result.reverseIndex(vars[i].srcidx, D)
    vars[i].destidx = result.reverseIndex(vars[i].destidx, desttotal)

  let (src, dest) = (genSym(nskLet, "src"), genSym(nskVar, "dest"))
  result.add:
    genAst(src, dest, srcexpr, desttotal,
           etctotal, srcetc=vars[etc].srcidx, destetc=vars[etc].destidx):
      var dest: IxMap[desttotal]
      let src = srcexpr
      dest.offset = src.offset
      for i in 1 .. etctotal:
        dest.shape[destetc+i] = src.shape[srcetc+i]
        dest.stride[destetc+i] = src.stride[srcetc+i]

  backward.reverse()
  assert vars.len() == forward.len() + backward.len() + 2
  for (i, expr) in pairs(forward & backward):
    let (what, srcidx, destidx) = vars[if i < etc: i + 1 else: vars.len + etc - 1 - i]
    assert not what.isNil
    result.add:
      genAst(src, dest, what, srcidx, destidx, expr):
        when what == 'c':
          let k = IxInt(when expr is BackwardsIndex: src.shape[srcidx] - expr.int else: expr)
          dest.offset += k * src.stride[srcidx]
        when what == 'k' or what == 's':
          dest.stride[destidx] = src.stride[srcidx]
          dest.shape[destidx] = src.shape[srcidx]
        when what == 's':
          sliceM(dest, destidx, expr)
        when what == 'n':
          let k = IxInt(expr)
          dest.shape[destidx] = k
          dest.stride[destidx] = 0

  result.add(dest)

  # echo "RESULT: ", result.treeRepr()
  result = newBlockStmt(result)
