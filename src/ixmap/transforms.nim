import std/math

import types
import axis

func reverse*[D: static[int]](x: sink IxMap[D], n: int): IxMap[D] {.inline.} =
  ## Reverses coordinates along a specific axis.
  x.offset += (x.shape[n] - 1)*x.stride[n]
  x.stride[n] = -x.stride[n]
  x

func reverse*[D: static[int]](x: sink IxMap[D]): IxMap[D] {.inline.} =
  ## Reverses coordinates along all axes.
  for i in 0 ..< D:
    x = x.reverse(i)
  x

func transpose*[D: static[int]](x: sink IxMap[D]): IxMap[D] {.inline.} =
  ## Transpose is defined as reversing the order of all axes.
  for i in 0 ..< D div 2:
    x.swapAxes(i, D - 1 - i)
  x

func diagonal*[D: static[int]](x: IxMap[D]): IxMap[1] {.inline.} =
  ## The coordinates along the diagonal of the original map.
  result.offset = x.offset
  result.shape[0] = min(x.shape)
  result.stride[0] = sum(x.stride)
