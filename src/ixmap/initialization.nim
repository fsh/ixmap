
import ./types
import ./ixarray

func normalize*[D: static[int]](x: var Ixmap[D]) {.inline.} =
  ## Nulls out the stride of axes that are one or less in length. This has no
  ## functional effect on the coordinates the index map describes, but is useful
  ## for broadcasting.
  for i in 0 ..< D:
    if x.shape[i] <= 1:
      x.stride[i] = 0

func initIxMap*[D: static[int], T, U](shape: array[D, T], stride: array[D, U], offset: int = 0): IxMap[D] =
  result.shape = shape.toIxArray()
  result.stride = stride.toIxArray()
  result.offset = offset
  result.normalize()

func initIxMap*[D: static[int], T](shape: array[D, T]): IxMap[D] =
  let shape = shape.toIxArray()
  initIxMap(shape, contiguousStrides(shape), 0)

func initIxMap*(offset: int): IxMap[0] =
  result.offset = offset

func revert*[D: static[int]](x: var IxMap[D]) =
  ## Reset strides and offset based on shape to their default state, so it
  ## is row-major covering the range `0 ..< size`.
  x.stride = contiguousStrides(x.shape)
  x.offset = 0

func initLoopIx*[D: static[int], T](shape: array[D, T]): IxMap[D] =
  # zero-initialize the rest
  result.shape = shape
