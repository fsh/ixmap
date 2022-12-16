
import ixarray
export ixarray

type
  IxMap*[D: static[int]] = object
    offset*: int
    shape*: IxArray[D]
    stride*: IxArray[D]



converter toIxArray*[D: static[int]; T: SomeInteger](x: array[D, T]): IxArray[D] {.inline.} =
  when T is IxInt:
    result = x
  else:
    for i, v in x:
      result[i] = IxInt(v)

converter toIntArray*[D: static[int]](x: IxArray[D]): array[D, int] {.inline.} =
  for i, v in x:
    result[i] = int(v)


converter toInt*(ix: IxMap[0]): int {.inline.} =
  ## 0-dimensional indices represents just a simple offset.
  ix.offset


type
  Axis* = range[0..63]
  StaticAxes* = static[set[Axis]] ## Compile-time known set of axes.
  AnyAxis* = StaticAxes | Axis | BackwardsIndex ## Axis types accepted as
                                                ## arguments by most functions.
  AxisSpec* = int | BackwardsIndex

const AllAxes* = {Axis.low .. Axis.high}

static:
  assert AllAxes is StaticAxes


iterator pairs*(axes: set[Axis]): (int, Axis) {.inline.} =
  var i = 0
  for v in axes:
    yield (i, v)
    i.inc

func orthogonal*(dim: Axis, axes: set[Axis]): set[Axis] =
  { Axis.low .. dim.pred } - axes

func filter*(dim: Axis, axes: set[Axis]): set[Axis] =
  axes * { Axis.low .. dim.pred }
