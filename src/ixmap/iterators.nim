
import std/strformat

import arrayutils

import types
import macros
import basic
import indexing

iterator offsets*[D: static[int]](src: IxMap[D]): int {.inline.} =
  var loopidx: IxArray[D]
  constrLoopTower(loopidx, src.shape):
    yield src ^@ loopidx

iterator coords*[D: static[int]](src: IxMap[D]): IxArray[D] {.inline.} =
  var loopidx: IxArray[D]
  constrLoopTower(loopidx, src.shape):
    yield loopidx

iterator coordOffsets*[D: static[int]](src: IxMap[D]): (IxArray[D], int) {.inline.} =
  var loopidx: IxArray[D]
  constrLoopTower(loopidx, src.shape):
    yield (loopidx, src ^@ loopidx)

# iterator iterSubIx*[D: static[int]](src: IxMap[D], N: static[int]): auto {.inline.} =
#   var (loop_ix, yield_ix) = src.split(N)
#   for o in offsets(loop_ix):
#     yield_ix.offset = o
#     yield yield_ix

iterator submaps*[D: static[int]](src: IxMap[D], axis: AxisSpec): auto {.inline.} =
  var src = src # tried using sink but sink params & iterators seem bugged?
  var (loop_ix, yield_ix) = src.popAxisM(axis)
  for o in offsets(loop_ix):
    yield_ix.offset = o
    yield yield_ix


iterator index*[T](u: var openArray[T], ix: IxMap): var T {.inline.} =
  ## Iterate over the items this index maps to in a given a flat `openArray`.
  for co in coords(ix):
    yield u[ix ^@ co]

iterator index*[T](u: openArray[T], ix: IxMap): lent T {.inline.} =
  ## Iterate over the items this index maps to in a given a flat `openArray`.
  for co in coords(ix):
    yield u[ix ^@ co]

iterator withCoords*[D: static[int], T](u: openArray[T], ix: IxMap[D]): (IxArray[D], lent T) {.inline.} =
  ## Iterate over the coordinates and items this index maps to in a given a flat
  ## `openArray`.
  for co in coords(ix):
    yield (co, u[ix ^@ co])

iterator withOffsets*[D: static[int], T](u: openArray[T], ix: IxMap[D]): (IxArray[D], lent T) {.inline.} =
  ## Iterate over the coordinates and items this index maps to in a given a flat
  ## `openArray`.
  for co in coords(ix):
    let offset = ix ^@ co
    yield (offset, u[offset])


# Q: How do I bind these in the `zipIndex` template without needing to export them?
iterator zipImpl2*[T1, T2](t: tuple[a: openArray[T1], b: openArray[T2]], ix1: IxMap, ix2: distinct IxMap): (lent T1, lent T2) {.inline.} =
  ## Workaround for Nim limitation.
  let bix = broadcast(ix1, ix2)
  for co in coords(bix):
    yield (t.a[ix1 ^@ co], t.b[ix2 ^@ co])

iterator zipImpl3*[T1, T2, T3](t: tuple[a: openArray[T1], b: openArray[T2], c: openArray[T3]], ix1: IxMap, ix2: distinct IxMap, ix3: distinct IxMap): (lent T1, lent T2, lent T3) {.inline.} =
  let bix = broadcast(ix1, ix2, ix3)
  for co in coords(bix):
    yield (t.a[ix1 ^@ co], t.b[ix2 ^@ co], t.c[ix3 ^@ co])


template zipIndex*(u: tuple, ix1: IxMap, ix2: distinct IxMap): untyped =
  ## Usage: `(seqlike1, seqlike2, ...).zipIndex(ix1, ix2, ...)`
  ##
  ## It takes a tuple as the first argument to work around a limitation in Nim.
  (u[0].toOpenArray(0, u[0].high), u[1].toOpenArray(0, u[1].high)).zipImpl2(ix1, ix2)

template zipIndex*(u: tuple, ix1: IxMap, ix2: distinct IxMap, ix3: distinct IxMap): untyped =
  (u[0].toOpenArray(0, u[0].high),
   u[1].toOpenArray(0, u[1].high),
   u[2].toOpenArray(0, u[2].high)).zipImpl3(ix1, ix2, ix3)
