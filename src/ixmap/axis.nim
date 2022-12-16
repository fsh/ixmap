
import types
import macros
import arrayutils
import strides

func newAxis*[D: static[int]](x: IxMap[D], dim: int | BackwardsIndex, num: int = 1): auto {.inline.} =
  ## Add a new axis at the given dimension.
  ##
  ## The axis will have length given by `num` (default 1) and stride 0 (so it
  ## can be infinitely repeated).
  when dim is BackwardsIndex:
    let dim = D - dim.int + 1
  assert dim >= 0 and dim <= D, "logic error; dimension index out of bounds"
  assert num >= 0, "length must be non-negative"
  var res: IxMap[D+1]
  res.shape = x.shape.insert(dim, IxInt(num))
  res.stride = x.stride.insert(dim, 0)
  res


func isRowMajor*(x: IxMap): bool =
  ## Row-major order is defined to be when strides run from higher to lower with
  ## higher dimensions.
  ##
  ## That is, variance in last dimension gives the smallest absolute variance in
  ## offset. Likewise, the first dimension increases or decreases the offset the
  ## most.
  ##
  ## If iterating over memory locations, iterating a row-major `IxMap`_ is *much*
  ## more efficient.
  ##
  result = true
  for i in 1 ..< x.ndims:
    if x.stride[pred(i)] < x.stride[i]:
      return false

proc makeRowMajor*(x: var IxMap) =
  constrStrideSort(x.ndims, x.stride, x.shape)


func toLinearSegment(ix: IxMap): LinearSegment[int,int] =
  result.initial = ix.offset
  result.count = -1

  var base = 0
  var i = ix.ndims
  while i > 0:
    i.dec
    if ix.stride[i] != 0:
      base = ix.stride[i]
      break

  var s = base
  while i > 0:
    i.dec
    if ix.shape[i] != 1:
      if ix.stride[i] != s:
        return
      s *= ix.shape[i]

  result.stride = base
  result.count = s

func isLinear(ix: IxMap): bool =
  ix.toLinearSegment().count >= 0

func toLinear(ix: IxMap): IxMap[1] =
  let seg = ix.toLinearSegment()
  assert seg.count >= 0

  result.offset = seg.initial
  result.shape[0] = seg.count.IxInt
  result.stride[0] = seg.stride.IxInt



proc swapAxes*[D: static[int]](ix: var IxMap[D], x, y: int) {.inline.} =
  ## Swap the order of the given axes.
  swap(ix.shape[x], ix.shape[y])
  swap(ix.stride[x], ix.stride[y])

proc buryAxis*[D: static[int]](ix: var IxMap[D], x: int) {.inline.} =
  ## Shift the axis currently at dimension `n` to the last dimension. Axes `n+1 ..< ix.dims` are shifted down one dimension.
  rollLeft(ix.shape, x .. D-1)
  rollLeft(ix.stride, x .. D-1)

proc liftAxis*[D: static[int]](ix: var IxMap[D], n: int) {.inline.} =
  ## Shift the axis currently at dimension `n` to the first dimension. Axes `0 ..< n` are shifted up one dimension.
  rollRight(ix.shape, 0 .. n)
  rollRight(ix.stride, 0 .. n)

proc split*[D: static[int]](src: IxMap[D], N: static[int]): auto {.inline.} =
  ## Splits the `IxMap` into two such that the first covers the first `N`
  ## dimensions and the second covers the remaining dimensions.
  ##
  ## `N` must be given as a *static* integer, i.e. it must be compile-time
  ## known, otherwise there would be no way to express the type of this function
  ## without dependent types.
  static:
    assert N <= D, "logic error; wrong dimension given"
  const M = D - N
  var ix_a: IxMap[N]
  var ix_b: IxMap[M]
  for i in 0 ..< N:
    ix_a.shape[i] = src.shape[i]
    ix_a.stride[i] = src.stride[i]
  for i in 0 ..< M:
    ix_b.shape[i] = src.shape[i+N]
    ix_b.stride[i] = src.stride[i+N]
  ix_a.offset = src.offset
  ix_b.offset = src.offset
  return (ix_a, ix_b)

proc popAxisM*[D: static[int]](src: var IxMap[D], axis: AxisSpec): auto {.inline.} =
  ## Splits the IxMap into two maps: one covering the given axis (or axes)
  ## and the other the remaining axes.
  ##
  ## This is done by essentially indexing the removed axes at 0.
  ##
  ## So splitting axis 0 is equivalent to `(ix[_, 0, 0, ...], ix[0, _, _, ...])`.
  when axis is int:
    src.liftAxis(axis)
    src.split(1)
  elif axis is BackwardsIndex:
    src.buryAxis(axis.int)
    src.split(D-1)
  elif axis is array:
    assert false, "todo"

proc popAxis*[D: static[int]](src: sink IxMap[D], axis: AxisSpec): auto {.inline.} =
  ## Splits the IxMap into two maps: one covering the given axis (or axes)
  ## and the other the remaining axes.
  ##
  ## This is done by essentially indexing the removed axes at 0.
  ##
  ## So splitting axis 0 is equivalent to `(ix[_, 0, 0, ...], ix[0, _, _, ...])`.
  src.popAxisM(axis)
