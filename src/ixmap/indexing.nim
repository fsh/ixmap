import std/macros as stdmacros

import strides
import types
import macros

import arrayutils


func `^@`*[D, N: static[int]](ix: IxMap[D], coords: array[N, IxInt]): int {.inline.} =
  shortDotProduct(ix.offset, ix.stride, coords)

func staticHackPred(x: int): int =
  ## Due to some bug in Nim compiler where it can't calculate static expressions
  ## in return type.
  assert x > 0, "Negative dimensionality is not allowed"
  x - 1

func collapse*[D: static[int]](x: IxMap[D], dim: int, idx: SomeInteger or BackwardsIndex): auto {.inline.} =
  assert dim >= 0 and dim < D, "logic error; dimension index out of bounds"
  let idx = idx ^! x.shape[dim]
  assert idx in (0 ..< x.shape[dim]), "out of bounds"

  var res: IxMap[D-1]
  res.offset = x.offset + idx * x.stride[dim]
  res.shape = x.shape.remove(dim)
  res.stride = x.stride.remove(dim)
  res




func sliceM*[D: static[int]](x: var IxMap[D], dim: int, idx: AnyStrided | HSlice) {.inline.} =
  assert dim >= 0 and dim < D, "logic error; dimension index out of bounds"

  when idx isnot LinearSegment:
    let idx = idx ^? x.shape[dim] # Lenient indexing.

  when idx is HSlice:
    x.offset += idx.a * x.stride[dim]
    if idx.len <= 1:
      x.stride[dim] = 0
  else:
    x.offset += idx.initial * x.stride[dim]
    if idx.len <= 1:
      x.stride[dim] = 0
    else:
      x.stride[dim] *= IxInt(idx.stride)

  x.shape[dim] = IxInt(idx.len)


func slice*[D: static[int], S](x: sink IxMap[D], dim: int, idx: S): IxMap[D] {.inline.} =
  x.sliceM(dim, idx)
  x


func select*(ix: IxMap, dim: static[int], idx: AnyIndexing): auto =
  static:
    assert dim >= 0 and dim < ix.ndims
  when idx is SomeInteger | BackwardsIndex:
    ix.collapse(dim, idx)
  else:
    ix.slice(dim, idx)


type
  NewAxis* = distinct int

func rep*(x: int): NewAxis {.inline.} = NewAxis(x)


macro `[]`*[D: static[int]](srcexpr: IxMap[D], idxs: varargs[untyped]): untyped =
  constrBracketIndex(D, srcexpr, idxs)
  # constrIndexing(D, srcexpr, ixs)

# macro `[]`*[D: static[int]](x: IxMap[D], ixs: varargs[untyped]): untyped =
#   var etc_found = false
#   var stack: seq[(NimNode, NimNode)]

#   var d = 0
#   var bumps = 0
#   for iexpr in children(ixs):
#     assert d >= 0 and d < D, "logic error; dimension index out of bounds"

#     if eqIdent(iexpr, "etc"):
#       assert not etc_found, "can only use `etc` once"
#       etc_found = true
#       d = D - (ixs.len() - d - 1)
#       continue

#     if eqIdent(iexpr, "new"):
#       d = D - (ixs.len() - d - 1)
#       continue

#     if eqIdent(iexpr, "_"):
#       ## Keep dimension as is: skip it.
#       d.inc
#       continue

#     quote:
#       type T = typeof(`iexpr`)
#       when T is SomeInteger or T is BackwardsIndex:
#         ix.collapse()
#     stack.add( (newLit(d), iexpr) )
#     d.inc

#   # We need to select indices in reverse order because a selection can shift
#   # following dimensions.
#   result = x.copy()
#   for (d, e) in stack.reversed():
#     result = newCall(ident("select"), result, d, e)
