import std/[strformat]
from std/macros as stdmacros import getAst

import ./arrayutils
import ./types
import ./macros
import ./initialization


template ndims*(x: IxMap): int =
  ## The dimensionality (number of axes) of the ixmap.
  ##
  ## This is part of the type itself and so is available statically.
  x.D

func size*(x: IxMap): int =
  ## Size is the product of shape: the size of all axes multiplied together.
  ##
  ## This is the number of iterations that `items()`, `coords()`, etc. will yield.
  ##
  ## Note that if one axis has length 0, the size will the 0.
  result = 1
  for s in x.shape:
    result *= s.int

func shape*[D: static[int]](x: IxMap[D]): IxArray[D] =
  ## Shape is a D-length array with the size (length) of each axis.
  x.shape

proc `$`*(x: IxMap): string =
  &"IxMap[{x.ndims}](shape={x.shape}, stride={x.stride}, offset={x.offset})"

proc `==`*[D1, D2: static[int]](x: IxMap[D1], y: IxMap[D2]): bool =
  when D1 != D2:
    false
  else:
    x.shape == y.shape and x.stride == y.stride and x.offset == y.offset

proc broadcast2*[D1, D2: static[int]](ix1: IxMap[D1], ix2: IxMap[D2]): auto {.inline.} =
  ## Concrete instance of `broadcast()` for two arguments.
  ##
  ## In general use the more general `broadcast()` macro; this is only exported in case a concrete proc is needed.
  let D = max(D1, D2)
  let h = longMax(ix1.shape, ix2.shape)
  let l = longMin(ix1.shape, ix2.shape)

  for i in 0 ..< D:
    if l[i] != h[i]:
      if l[i] != 1:
        raise newException(ValueError, &"cannot broadcast {ix1.shape} and {ix2.shape}")
      assert i >= D1 or ix1.shape[i] == h[i] or ix1.stride[i] == 0, "internal error: stride should be 0"
      assert i >= D2 or ix2.shape[i] == h[i] or ix2.stride[i] == 0, "internal error: stride should be 0"

  initLoopIx(h)

# Q: having the first argument be `IxMap` typed leads to this kind of error:
#
# Error: type mismatch: got <IxMap, IxMap[2]> but expected one of:
# proc broadcast2[D1, D2: static[int]](ix1: IxMap[D1]; ix2: IxMap[D2]): auto
#   first type mismatch at position: 1
#   required type for ix1: IxMap[broadcast2.D1]
#   but expression 't2`gensym454.ix' is of type: IxMap
#
# How to fix that?
macro broadcast*(ix: untyped, rest: varargs[untyped]): auto {.inline.} =
  ## Creates "loop index" which is in some sense the union (or "meet") of the
  ## given index maps. A loop index is an index map with all-zero strides, thus
  ## it only makes sense to loop over its coordinates.
  ##
  ## The dimension `D` of the returned index map matches the highest dimension
  ## among the arguments. The length of each axis is the maximum of any maps'
  ## axis at that dimension.
  ##
  ## However, differing lengths of a particular axis is _only_ allowed if the
  ## non-maximal length is missing or equal to 1 (and its stride is 0).
  ## Otherwise it is an error (`ValueError`). This means that `[1, 20, 5]`
  ## broadcasts with `[10, 1]`, but not with `[10, 10]` (fails in the second
  ## dimension).
  ##
  ## Example:
  ##
  ## Let `A` with shape `[1, 5]` be a tensor that is akin to a matrix consisting
  ## of a single row. Let `B` with shape `[10, 1, 10]` be a 3d tensor (could be
  ## thought of as a single-column square sliver inside a 10×N×10 box array).
  ##
  ## Now imagine going through every index in the `A` row and placing the sliver
  ## `B` there (in that column). The broadcast is all indices thus reached. This
  ## is the same as if you imagine travering over the "matrix" of `B` and
  ## placing the `A` row at every position.
  ##
  ## Consider also:
  ##
  ## - a scalar index acts as an identity for this operation.
  ##
  ## - Only the "space" covered by the index map matters: the intuitive
  ##   "direction" of an axes (into your storage) does not matter as that is a
  ##   matter of stride and not the space.
  ##
  ##`A` will be augmented with a
  ## third axis, and its row-dimension will be repeated to match `B`; whilst
  ## `B`s column-dimension will be repeated to match `A`. The result is a `[10,
  ## 5, 10]` tensor where index `[x,y,z]` describes `A[0, y]` and `B[x, 0, z]`.
  ##
  getAst(foldArgsR(broadcast2, ix, rest))
