
type
  IxInt* = int32
  IxArray*[D: static[int]] = array[D, IxInt]


func contiguousStrides*[D: static[int]](shape: IxArray[D]): IxArray[D] =
  var s: IxInt = 1
  for i in countdown(shape.high, 0):
    if shape[i] != 1:
      result[i] = s
      s *= shape[i]
    # else: keep zero-initialization
