when NimVersion >= "1.7":
  # For some reason Nim 1.6 rejects file pragma.
  {.doctype: rst.}

## =============
## IxMap Purpose
## =============
##
## `IxMap` is an efficient abstraction for *indexing of multidimensional
## arrays* (also known as ndarrays or tensors).
##
## If you are familiar with other libaries such as `Arraymancer` (Nim),
## `NumPy` (Python), `ndarray` (Rust), or Julia's own built-in array types, then
## you'll know most of the basics of multidimensional indexing already.
##
## Roughly speaking you can think of `IxMap[D]` as a function (using `[]` rather
## than `()`) of (up to) `D` integer coordinates to a single integer
## offset.
##
## Overview of Use Cases
## ---------------------
##
## The most basic use case is to provide a map between `[x,y,z,...]`-style
## indexing and a scalar `int` (which might describe an offset into a flat array,
## linear database, or memory store).
##
## This library is a set of types and functions to make *indexing* as efficient
## and ergonomic as possible. It exists completely independent of any actual
## tensor or ndarray *implementation*. `IxMap` only handles the creation of
## views, slices, iteration, and so on, it does not manage any actual data. Its
## intended use is in those other implementations, or to be used stand-alone
## when certain kinds of nested iteration is desired.
##
## Consider a contiguous sequence of 1000 numbers in memory called `S`. This could
## be interpreted in many different ways, *depending only on how we index it*:
##
## - a vector of 1000 elements, indexing it directly like `S[i]`.
## - matrix with 50 columns and 20 rows, or 20 rows and 50 columns, indexing it like `S[r * 20 + c]` or `S[r * 50 + c]` respectively,
## - 5×5×40 box of values,
## - a mapping from three booleans to 5×5×5 cubes of values (essentially 2×2×2×5×5×5), which
##   we might index as `S[b0.int * 500 + b1.int * 250 + b2.int * 125 + x * 25 + y * 5 + z]`,
## - an highly redundant matrix a *billion* copies of the same 1000-element row, by using `S[r * 0 + c]`,
## - ... and so on
##
## No matter what view we hold, there's many common operations we might want to do:
##
## - form an iterator over the elements in a certain order, or only elements in certain rows, columns, layers, etc.,
## - form a "view" into the data by limiting our consideration to some subregion (slice, submatrix, subbox),
## - consider a region "as if" it has been reversed, flipped, or transposed in some way, _without actually moving the data around_,
## - introduce new axes simulating redundancy (for example an array where each location contains the same value need only actually store that single value),
##
## All these situations can be handled by `IxMap` (with caveats) in a manner that is
## optimally [#optimal]_ space- and time-efficient.
##
## Indexing
## --------
##
## The bracket operator `[]` produces new index maps, and has some special
## semantics:
##
## If the index at the given axis is `_` then this axis is left alone.
## (Equivalent to slicing the entire range, like `0 .. ^1`.)
##
## The number of arguments given to `[]` need not match the rank. Any trailing dimenisons
## will act as if they were selected with `_`.
##
## A primitive integer value selects that particular index (row, column, layer,
## etc) at the given axis, thus collapsing it. This means the rank is reduced
## by one. If `ix` has 3 dimensions (here arbitrarily named `row × column × depth`),
## then `ix[0,2]` will have a single dimension: a vector index of the `depth`s
## of the first row and third column. Likewise `ix[_, _, 0]` can be thought of
## as the indices of the `row × column` matrix of the first level.
##
## Backwards indices `^i` work as expected. Slicing `a .. b` and `a ..< b` also
## work as expected.
##
## .. note:: `ix[5..5]` is fundamentally different from
##   `ix[5]` as it merely reduces the first axis to length 1, but does not collapse it.
##   Thus the two expressions yield a different return type.
##
## `IxMap` employs (and re-exports) the `stride` library, so supports full linear slicing. Meaning
## that strided slicing (slice with a step) and reversing of axes can also be performed:
##
## - To add a stride, use the `@:` operator. `a .. b @: n` represents
##   every `n`\ th value in the range, starting with `a`.
##
##   For example `0 .. 30 @: 4` is a strided slice referring to values `[0, 4, 8, 12, 16, 20, 24, 28]` in that order.
##
## - The stride may also be negative and can be used to reverse an axis: `9 .. 0 @: -1` refers to values `[9, 8, 7, 6, 5, 4, 3, 2, 1, 0]` in that order.
##
## - `@: n` is short-hand for `0 .. ^1 @: n` or `^1 .. 0 @: n` (depending on whether `n` is positive or negative).
##
## - `len @: n` is short-hand for `0 ..< len @: n` or `len-1 .. 0 @: n` (again depending on whether `n` is positive or negative).
##
## For more information, see the `strides` library.
##
## The special identifier `etc` expands to cover all missing axes at the given
## position, leaving them untouched. Think of it as an ellipsis `...`.
##
## - If `ix` is a 2-dimenisional `IxMap` then `ix[1, etc, 2]` is equivalent to `ix[1, 2]`.
## - If `ix` is 3-dimenisional it is equivalent to `ix[1, _, 2]`.
## - If `ix` is 4-dimenisional it is equivalent to `ix[1, _, _, 2]`.
## - ... and so on.
##
## .. note:: If `etc` is not used explicitly then it is implicitly added to the end. E.g.
##   `ix[i, j]` is implicitly interpreted as `ix[i, j, etc]`.
##
## Indexing is done with macros since the return type depends on the given arguments.
## Given that function inlining is done correctly, it should compile down to the most efficient
## possible code path.
##
## Technical Details
## -----------------
##
## An `IxMap[D]` describes a `D`-dimensional indexing structure, e.g. `[0 ..
## rows-1] × [0 .. cols-1] × ...`. The dimensionality (also known as rank, or
## number of axes) is static and part of the type:
##
## - `IxMap[0]` is a scalar. Its size is simply the size of an `int`, nothing more. It refers to a single concrete index.
## - `IxMap[1]` describes a vector. It refers to a number of linearly spaced items. Its size of an `int` plus a length and a stride (32-bit each by default), so 16 bytes on a modern 64-bit computer.
## - `IxMap[2]` describes a matrix. It would be 24 bytes on a 64-bit computer.
## - `IxMap[3]` describes a 3D box or a 3-cell; or it can be thought of as a matrix of vectors, or a number of stacked matrices.
## - ... and so on.
##
## In general the size of `IxMap[D]` is the size of `IxMap[D-1]` plus a length and a stride describing the extra axis.
##
## An `ix: IxMap[D]` has these fundamental properties:
##
## - `ix.ndims`: number of dimensions, `D`. This is static and available at compile-time; it is not stored at run-time.
## - `ix.offset`: the base offset of this indexing view; it would be the element `ix[0,0,0,...]`.
## - `ix.shape`: an array of `D` integers giving the length of each axis.
## - `ix.stride`: an array of `D` integers giving the stride (length between each consecutive element along this axis).
##
## .. note:: With a `IxMap[0]` the arrays will be of length 0 and thus vanish so only the offset remains.
##
## There is also `ix.size` which gives the total number of distinct indices this map has as a
## product of its shape (i.e. `ix.size == ix.shape[0] * ix.shape[1] * ...`).
##
## For example a matrix-like index `m` with 100 rows and 50 columns and row-first indexing
## (`m[r,c]`) will have shape `[100,50]`, size `5000`, ndims `2`, and stride
## might be something like `[50, 1]`.
##
## .. note:: This does *not* mean the tensor or ndarray has to store this many elements; many indices could refer to the same element in memory.
##
## Benefits & Practical Use
## ------------------------
##
## The primary benefit of this kind of structure is it allows us to form several "views"
## of the same data without having to copy or move any memory. Many basic operations
## involve merely shifting some offsets or modifying the stride.
##
## Continuing with the previous example of the 100×50 matrix index:
##
## - To form a new index referring to a 10×10 submatrix, for example `m[10 ..< 20, 35..<
##   45]`, we just need set the new shape to `[10,10]` and update the offset to
##   match `m[10,35]`.
##
## - Viewing the matrix such that the rows are in reverse order (with `m[@: -1, _]`)
##   is just a negating the stride and again shifting the base offset. (The `@:` operator here is from the
##   `strides` library.)
##
## - To transpose the matrix (`m.transpose`) we simply switch the two axes.
##
## - To form a vector-like view of a specefic column in the matrix (e.g. `m[_, 5]`), we can shift the base
##   offset to that column and then simply forget about the column axis.
##
## Notice that none of these operations need to copy, move, or even know about
## the memory or data store of the elements we're indexing, as long as the
## original index `m` was correct.
##
## - Another trick we can do for free is to inject a new axis of whatever
##   length we want while setting its stride to `0`, simulating duplicating all
##   the data along that axis. This forms the basis of something called
##   broadcasting.
##
## - And we can also have the axes map to overlapping regions in various ways.
##   For example we can have a functional index for a full `n×n` `circulant
##   matrix <https://en.wikipedia.org/wiki/Circulant_matrix>`_ backed by an
##   array of only `2n - 1` elements, with no need to specialize code for it.
##
## Iteration
## ---------
##
## `IxMap` can be iterated over directly in three ways:
##
## - `items(ix)` iterates in a row-major fashion yielding the offsets as `int` values.
##   It is roughly equivalent to:
##
##   .. code-block::
##     for co0 in 0 ..< ix.shape[0]:
##       for co1 in 0 ..< ix.shape[1]:
##         ...
##           for coLast in 0 ..< ix.shape[D-1]:
##             yield co0 * ix.stride[0] + co1 * ix.stride[1] + ... + coLast * ix.stride[D-1]
##
##    .. note:: Optimization pass will strength-reduce the multiplications to additions and hoist them out of the inner loop.
##
## - `coords(x)` yields arrays of `D` elements, representing the actual coordinates (indices).
##   In the last example this is equivalent to `yield [co0, co1, ..., coLast]`.
##
## - `pairs(x)` yields `(array[D, IxInt], int)`, like zipping the former two iterators.
##
## Limitations
## -----------
##
## Index structures with *runtime-only rank* are not supported, tho this rarely
## comes up in practice (and the rank is usually quite small and can be
## specialized anyway).
##
## Another limitation is the fact that the actual shape is opaque from a
## compile-time perspective. The only major functionality I have seen in the
## while where this becomes a problem is in having a `squeeze` function, which
## would remove all axes with length 1. The type of such a function is
## impossible to express in a language like Nim which lacks dependent types.
## (We could still have a macro which takes a block that *receives* such a type, but
## we could never actually return it or branch on it.)
##
## One way to offset this problem is to encode (on a type level) certain information
## about the axes. Let's say we instead used `IxMap[A]` where `A` was a compile-time static
## value `array[int, AxisType]`. In that case the rank would be `A.len` and `A[n]` might
## indicate that a specific axis was a "singleton axis." In that case we could strip
## such compile-time known singleton axes. We could also introduce the concept of
## "compact" axes whose stride is statically inferrable, and so we do not need to carry
## around information about their strides. Example would be a plain row-major index
## where no slicing or striding has been performed.
##
## Of course we wouldn't know if a length-1 axis was constructed dynamically,
## but we would at least recognize statically added axes and could remove those.
##
## However, I have yet to find a way to make this system work in Nim as it seems
## to push the boundary of what its type system is capable of w.r.t. `static[]`
## values(?).
##
## TODO: a "hack" to get around this Nim limitation is to still use a
## `static[int]`, but interpret the int by its octal digits; `0o123` could mean
## 3 dimensions where each axis is of a different type (for example an *aligned
## axis* with inferrable stride, a *strided axis* with dynamic stride, and a
## statically added *singleton axis*).
##

## .. [#optimal] usually `O(D)` where `D` is the number of dimensions, but this is
##   always static, so essentially `O(1)`. Another potential inefficiency is
##   that strides are stored for all axes, even when those axes might have
##   statically inferrable stride; see also `limitations`_.
##

import ixmap/types
export types

import ixmap/axis
export axis

import ixmap/initialization
export initialization

import ixmap/basic
export basic

import ixmap/indexing
export indexing

import ixmap/iterators
export iterators

import ixmap/transforms
export transforms

