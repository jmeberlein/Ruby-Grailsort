# Properties of a Sorting Algorithm

Okay, what makes a good sorting algorithm. There are other properties people will look at when comparing sorting algorithms, such as best case performance as distinct from average or worst case. But there are three properties which are particularly common, but unfortunately form a "you can only pick two" situation.

## Stable Sorting

Stability, in the context of sorting algorithms, refers to how an algorithm handles ties. An unstable sorting algorithm treats equal elements as interchangeable, while a stable sorting algorithm breaks ties by looking at the original order. For example, if you were sorting a deck of cards, an unstable sort would only make sure the aces are together, while a stable sort would ensure they remain in their original order. There *are* times when stability is unimportant. For example, primitive types have little enough identity that they *are* functionally interchangeable. Or all other things considered, unstable sorting algorithms run more quickly than stable ones, so if you really don't care about stability, you can reduce execution time. However, because you can always use a stable sort when you don't need this property, but you can't trivially adapt an unstable sorting algorithm for when you need a stable one, I'm of the opinion that standard libraries should default to stable algorithms. And, well, Enumerable.sort in Ruby is unstable.

## Average Case Time Complexity

Time complexity, typically expressed in Big-O notation, refers to how quickly the execution time grows as a function of the input size. For example, an algorithm that runs in O(n log n) (linearithmic) time generally runs more quickly than an algorithm that runs in O(n^(2)) time. The *vast* majority of sorting algorithms, unless you get into the silly ones like Stooge sort, fall into one of these two categories. However, there are some caveats. First, this is just a *trend*. So while a O(n log n) algorithm will *eventually* always be faster as you increase the input size, it's possible for the reverse to be true for small inputs. For example, the fancy linearithmic sorts tend to be overkill for small arrays, so it's faster to just use a "dumb" sort like insertion sort. And second, this is only the *average* case, but it's possible for algorithms to be faster or slower for certain inputs. For example, insertion sort runs in O(n) time on arrays that are already sorted, while quicksort runs in O(n^(2)) time on particularly ill-suited arrays.

## Space Complexity

This is similar to time complexity, but looking at memory usage instead. This can get really complicated really quickly. For example, calling a method technically takes up stack space, so technically, a top-down mergesort is O(n log n) space because of the recursion, even if you can optimize the buffers to only require a total of n-1 elements, which would otherwise be O(n).

The definition of "in-place" I'm using here is O(1) space complexity, which essentially means that it takes up a constant amount of memory, regardless of the input size, obviously ignoring the need to store the array itself. And because none of the helper methods involved in this algorithm are recursive, I'm treating all the methods being O(1) locally as a sufficient condition to call the entire algorithm in-place.

# Grailsort

Yeah, it's the holy grail of sorting algorithms, hence the name. It manages to do funky things with splitting the array into blocks to perform a mergesort with a fixed-size external buffer. *Strictly speaking*, this runs in O(n log^(2) n) time, because it uses a rotation-based merge sort for the degenerate case where there are only 1-3 distinct elements in the array. And because that condition isn't based on input size, you can't use technicalities to brush it away, like when algorithms will switch to a quadratic algorithm for small inputs. But apart from that specific case, this algorithm meets all three of those requirements - stable, O(n log n) average case, and in-place.

This implementation is *largely* based on the Rust implementation found [here](https://github.com/HolyGrailSortProject/Rewritten-Grailsort), but with a few changes. I'm not concerned with anything like the explicit external buffer, and I'm not concerned with only sorting a subarray. So all of the out-of-place methods can be skipped, and a lot of parameters can be removed. (And I'm actually occasionally using the Zig implementation for reference instead, because it makes those same design choices) Additionally, I'm adding a few optimizations of my own, such as removing some of the swap-based methods. Using pairwise_swaps vs pairwise_writes as an example, pairwise_writes already meets my definition of in-place *and* is faster, so I'm not bothering with the version that removes almost all buffer space by swapping elements. Or I also introduced a new block reversal algorithm, based on the conjoined triple rotation algorithm, which can handle corner cases like when the blocks to be merged just need to be swapped, but the buffer still needs to be moved to after them. But otherwise, this is intended to be a Ruby translation of Rewritten Grailsort, just with copious added comments for documentation.

# TODO

* Finish implementing it (obviously)
* Add proper unit tests, as opposed to just testing things in IRB as I go
* Upgrade this into a proper gem, as opposed to just being this README and a mono-file