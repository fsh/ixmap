
import std/macros as stdmacro

import std/[sequtils]

import pkg/strides

import ixmap/axis
import ixmap/macros
import ixmap

import unittest

#
suite "misc":
  proc sortpermute[I,T](x, y, z: var array[I,T]) =
    constrStrideSort(x.len, x, y, z)

  test "sort-permute 1":
    var
      x = [1,2,3]
      y = [3,1,2]
      z = [2,1,3]

    sortpermute(x, y, z)
    check x == [3,2,1] and y == [2,1,3] and z == [3,1,2]
    sortpermute(x, y, z)
    check x == [3,2,1] and y == [2,1,3] and z == [3,1,2]
    sortpermute(z, x, y)
    check x == [3,1,2] and y == [2,3,1] and z == [3,2,1]

  test "sort-permute 2":
    var
      x = [1,2]
      y = [-1,-2]
      z1 = [10,9,8,7,6,5,4,3,2,1]
      z2 = [1,2,3,4,5,6,7,8,9,10]
      zs = [10,9,8,7,6,5,4,3,2,1]
      zr = [1,2,3,4,5,6,7,8,9,10]

    constrStrideSort(2.Axis, x, y)
    check x == [2,1] and y == [-2,-1]
    check z1 == zs and z2 == zr
    constrStrideSort(10.Axis, z1, z2)
    check z1 == zs and z2 == zr
    constrStrideSort(10.Axis, z2)
    check z1 == z2

  test "axis type":
    check 0.Axis.orthogonal({1.Axis}).len == 0
    check 4.Axis.orthogonal({1.Axis}).len == 3

  test "ixarray":
    let ix = [1,2,3].toIxArray
    check ix is IxArray[3]
    check ix.toIntArray is array[3, int]
    check ix.toIntArray == [1,2,3]


suite "sanity":
  test "init":
    # shape, stride, offset
    check initIxMap([1,2,3], [3,3,3], 1) is IxMap[3]
    # shape, stride
    check initIxMap([1,2,3], [3,3,3]) is IxMap[3]
    # shape only
    check initIxMap([1,2,3]) is IxMap[3]
    # offset only
    check initIxMap(0) is IxMap[0]

    # loopix
    block:
      let li = initLoopIx([5,5])
      check li is IxMap[2]
      check li.shape == [5,5].toIxArray
      check li.stride == [0,0].toIxArray

  test "row-major":
    var x = initIxMap([1,2,3], [1,2,3])
    check x is IxMap[3]
    check not x.isRowMajor()
    x.makeRowMajor()
    check x.isRowMajor()
    check x.shape == [3,2,1].toIxArray

suite "ixmap":
  setup:
    let ix3 = initIxMap([5,3,2])

  test "properties":
    check $ix3 == "IxMap[3](shape=[5, 3, 2], stride=[6, 2, 1], offset=0)"

    check ix3.ndims == 3
    check ix3.stride.toIntArray == [6,2,1]
    check ix3.size == 30
    check ix3.shape.toIntArray == [5, 3, 2]

    check ix3 == ix3
    check ix3 == initIxMap([5,3,2])
    check ix3 != initIxMap([5,2,3])

    let other = initIxMap([2,2,2,0,2,2], [9,9,9,9,9,9])

    check other.size == 0
    check other != ix3
    check other != initIxMap([2,2,2,0,2,2]) # stride missing

  suite "indexing":
    test "lookup":
      check ix3 ^@ [0,0,0] == 0
      check ix3 ^@ [1,1,1] == 6 + 2 + 1
      check ix3 ^@ [3,2,1] == 3*6 + 2*2 + 1

      # truncated lookup
      check ix3 ^@ [1] == 6

    test "basic":
      check ix3[0,0,0] is IxMap[0]
      check ix3[0] == initIxMap([3,2], [2,1], 0)
      check ix3[3,2,1] == ix3[3][2][1]

    test "slicing":
      check ix3[0..2,0,0] == initIxMap([3], [6], 0)
      check ix3[1..0,0,0] == initIxMap([0], [6], 6)
      check ix3[-5 .. 10] == ix3 # lenient with slices

      # stride gets nulled out
      check ix3[1..1,0,0] == initIxMap([1], [0], 6)

      check ix3[^3,^2,^1] == ix3[2,1,1]
      check ix3[1 .. ^1] == ix3[1..4]

      check ix3[0 .. -1].size == 0

    test "special":
      check ix3[_,2] == initIxMap([5,2], [6,1], 4)
      check ix3[etc,1] == initIxMap([5,3], [6,2], 1)
      check ix3[_,_,1] == initIxMap([5,3], [6,2], 1)
      check ix3[_,1,_] == initIxMap([5,2], [6,1], 2)
      check ix3[1,etc,1] == initIxMap([3], [2], 7)

    test "new axes":
      check ix3.newAxis(0) == initIxMap([1,5,3,2], [0,6,2,1], 0)
      check ix3.newAxis(1) == initIxMap([5,1,3,2], [6,1,2,1], 0)
      check ix3.newAxis(3) == initIxMap([5,3,2,1], [6,2,1,0], 0)
      check ix3.newAxis(^1) == initIxMap([5,3,2,1], [6,2,1,0], 0)

    test "strided":
      check ix3[0 .. ^1 @: 2] == initIxMap([3, 3, 2], [12, 2, 1], 0)

      check ix3[3 @: 2] == ix3[0..2 @: 2]
      check ix3[0 .. ^1 @: 10, 0 .. ^1 @: 10, 0 .. ^1 @: 10] == initIxMap([1,1,1], [0,0,0], 0)

suite "looping":
  setup:
    let ix2 = initIxMap([5,4])
    let ix3 = initIxMap([5,4,3])

  test "loop":
    var xs = newSeq[int]()

    let voff = offsets(ix2).toSeq()
    check voff[0..3] == @[0, 1, 2, 3]

    let coff = coords(ix2).toSeq()
    check coff[0..4] == @[ [IxInt(0),0], [0,1], [0,2], [0,3], [1,0] ]

    let cos = coordOffsets(ix2).toSeq()
    check cos[0..4] == @[
      ([0,0].toIxArray, 0),
      ([0,1].toIxArray, 1),
      ([0,2].toIxArray, 2),
      ([0,3].toIxArray, 3),
      ([1,0].toIxArray, 4) ]

  test "submaps":
    for ix in ix3.submaps(0):
      check ix.ndims == 2
      check ix.shape == [IxInt(4), 3]
      check ix.offset mod 12 == 0

    for ix in ix3.submaps(1):
      check ix.ndims == 2
      check ix.shape == [IxInt(5), 3]
      check ix.offset mod 3 == 0

    for ix in ix3.submaps(2):
      check ix.ndims == 2
      check ix.shape == [IxInt(5), 4]
      check ix.offset < 3

    for ix in ix3.submaps(^1):
      check ix.ndims == 1
      check ix.shape == [IxInt(4)]

suite "axes":
  setup:
    var ix3 = initIxMap([5,4,3])

  test "swap":
    check ix3[1,0,0].toInt == 4*3
    ix3.swapAxes(0, 1)
    check ix3.shape == [IxInt(4),5,3]
    check ix3[1,0,0].toInt == 3

  test "bury":
    check ix3[0,0,1].toInt == 1
    ix3.buryAxis(1)
    check ix3.shape == [IxInt(5),3,4]
    check ix3[0,0,1].toInt == 3

  test "lift":
    check ix3[1,0,0].toInt == 12
    ix3.liftAxis(1)
    check ix3.shape == [IxInt(4),5,3]
    check ix3[1,0,0].toInt == 3
