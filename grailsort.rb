# frozen_string_literal: true

require_relative "grailsort/version"

module Grailsort
  ###############
  # ENTRYPOINTS #
  ###############
  def self.grailsort!(arr, &cmp)
    cmp ||= Proc.new { |a,b| a <=> b }
    common_sort!(arr, &cmp)
  end

  def self.grailsort_by!(arr, &by)
    hash = arr.zip(arr.map(&by))
    common_sort!(hash) { |a,b| a[1] <=> b[1] }
    hash.map { |e, _| e }
  end

  #############
  # CORE SORT #
  #############

  def self.common_sort!(arr, &cmp)
    # Grailsort requires a list of 16+ elements, so default to insertion sort for lists below that length
    if arr.count < 16
      insertion_sort!(arr, 0, arr.count, &cmp)
      return
    end

    # Round the square root of the array length up to a power of two
    block_len = 1
    block_len *= 2 while block_len**2 < arr.count

    # Integer division, but rounding *up* instead of down
    key_len = ((arr.count - 1) / block_len) + 1
    ideal_keys = key_len + block_len
    keys_found = collect_keys!(arr, 0, arr.count, ideal_keys, &cmp)

    # Grailsort can *attempt* to adapt if there aren't enough distinct values, but if there are only 1-3 distinct 
    # values, it's easier to just default to a rotation merge sort
    #
    # Because the keys are the first instances of the values, this will also stably re-insert the keys into the body 
    # of the array
    if keys_found < 4
      lazy_stable_sort!(arr, 0, arr.count, &cmp)
      return
    end

    if keys_found < ideal_keys
      key_len = block_len
      block_len = 0
      ideal_buffer = false
      key_len /= 2 while key_len > keys_found
    else
      ideal_buffer = true
    end

    buffer_end = block_len + key_len
    subarray_len = ideal_buffer ? block_len : key_len

    build_blocks!(arr, buffer_end, subarray_len, &cmp)

    # TODO: Finish method
  end

  # Attempt to find ideal_keys unique values and move them to the front of the array, then return the actual number 
  # of keys found
  #
  # For each value in the array, either rotate it into position in the growing list of keys OR move it to before 
  # the list of keys, if it isn't a new unique value. Once enough keys have been found or the list is exhausted, 
  # rotate the block of keys to before the duplicates
  def self.collect_keys!(arr, start, length, ideal_keys, &cmp)
    keys_found = 1
    first_key = 0
    current_key = 1

    while current_key < length && keys_found < ideal_keys
      insert_pos = binary_search_left(arr, start + first_key, keys_found, arr[start + current_key], &cmp)
      if insert_pos == keys_found || yield(arr[start + current_key], arr[start + first_key + insert_pos]) != 0
        rotate!(arr, start + first_key, keys_found, current_key - (first_key + keys_found))
        first_key = current_key - keys_found
        rotate!(arr, start + first_key + insert_pos, keys_found - insert_pos, 1)
        keys_found += 1
      end
      current_key += 1
    end
    rotate!(arr, start, first_key, keys_found)
    keys_found
  end

  ##################
  # ROTATION MERGE #
  ##################

  # This algorithm technically runs in O(n log^2 n) time, which is slower than the ideal O(n log n). 
  # However, coefficients matter, so similarly to how insertion sort is overall faster for small arrays, 
  # rotation merge is overall faster for arrays with a small number of distinct keys

  def self.lazy_stable_sort!(arr, start, length, &cmp)
    (1...length).step(2) do |i|
      left, right = start + i - 1, start + i
      if yield(arr[left], arr[right]) > 0
        arr[left], arr[right] = arr[right], arr[left]
      end
    end

    merge_len = 2
    while merge_len < length
      merge_index = 0
      merge_end = length - 2*merge_len

      while merge_index <= merge_end
        lazy_merge!(arr, start + merge_index, merge_len, merge_len, &cmp)
        merge_index += 2*merge_len
      end

      leftover = length - merge_index
      if leftover > merge_len
        lazy_merge!(arr, start + merge_index, merge_len, leftover - merge_len, &cmp)
      end

      merge_len *= 2
    end
  end

  def self.lazy_merge!(arr, start, left, right, &cmp)
    if left < right
      while !left.zero?
        insert_pos = binary_search_left(arr, start+left, right, arr[start], &cmp)

        if !insert_pos.zero?
          rotate!(arr, start, left, insert_pos)
          start += insert_pos
          right -= insert_pos
        end

        break if right.zero?

        start += 1
        left -= 1
        while !left.zero? && yield(arr[start], arr[start+left]) <= 0
          start += 1
          left -= 1
        end
      end
    else
      ptr_end = start + left + right - 1
      while !right.zero?
        insert_pos = binary_search_right(arr, start, left, arr[ptr_end], &cmp)

        if insert_pos != left
          rotate!(arr, start + insert_pos, left - insert_pos, right)
          ptr_end -= left - insert_pos
          left = insert_pos
        end

        break if left.zero?

        left_end = start + left - 1
        ptr_end -= 1
        right -= 1
        while !right.zero? && yield(arr[left_end], arr[ptr_end]) <= 0
          ptr_end -= 1
          right -= 1
        end
      end
    end
  end

  ###############
  # BASIC MERGE #
  ###############

  # Perform most of the merge steps. Start by sorting pairs of elements, while moving a buffer of 2 elements 
  # to the end of the array. Then start higher order merges, using a buffer of 2 elements to merge pairs of blocks 
  # of 2 elements, a buffer of 4 elements to merge pairs of blocks of 4 elements, etc. Once the buffer is exhausted,
  # use the accumulated buffer at the end to perform one last merge step. For example:
  #
  # +----------+----------+----------+----------------+
  # | Buffer-4 | Buffer-2 | Buffer-2 | Unsorted array |
  # +----------+----------+----------+----------------+
  # 
  # +----------+----------+--------------+--------+
  # | Buffer-4 | Buffer-2 | Sorted pairs | Buffer |
  # +----------+----------+--------------+--------+
  #
  # +----------+--------------+--------+
  # | Buffer-4 | Sorted fours | Buffer |
  # +----------+--------------+--------+
  #
  # +---------------+----------+
  # | Sorted eights | Buffer-8 |
  # +---------------+----------+
  #
  # +--------+-----------------+
  # | Buffer | Sorted sixteens |
  # +--------+-----------------+
  def self.build_blocks!(arr, start, buffer_len, &cmp)
    pairwise_swaps!(arr, start, arr.count - start, &cmp)
    build_in_place!(arr, start - 2, arr.count - start, buffer_len, &cmp)
  end

  def self.pairwise_swaps!(arr, start, length, &cmp)
    buff = arr[start-2], arr[start-1]
    (0...length).step(2) do |i|
      left, right = start+i, start+i+1

      if yield(arr[left], arr[right]) <= 0
        arr[left-2], arr[left-1] = arr[left], arr[right]
      else
        arr[left-2], arr[left-1] = arr[right], arr[left]
      end
    end

    if length.odd?
      arr[start+length-3] = arr[start+length-1]
    end

    arr[start+length-2], arr[start+length-1] = buff
  end

  def self.build_in_place!(arr, start, length, buffer_len, &cmp)
    merge_len = 2
    while merge_len < buffer_len
      merge_index = start
      both_merges = 2 * merge_len
      merge_end = start + length - both_merges
      buffer_offset = merge_len

      while merge_index <= merge_end
        merge_forwards!(arr, merge_index, merge_len, merge_len, buffer_offset, &cmp)
        merge_index += both_merges
      end

      leftover = length - (merge_index - start)

      if leftover > merge_len
        merge_forwards!(arr, merge_index, merge_len, leftover - merge_len, buffer_offset, &cmp)
      else
        rotate!(arr, merge_index - merge_len, merge_len, leftover)
      end

      start -= merge_len
      merge_len *= 2
    end

    both_merges = 2 * buffer_len
    final_block = length % both_merges
    final_offset = start + length - final_block
    if final_block <= buffer_len
      rotate!(arr, final_offset, final_block, buffer_len)
    else
      merge_backwards!(arr, final_offset, buffer_len, final_block - buffer_len, buffer_len, &cmp)
    end

    merge_index = final_offset - both_merges
    while merge_index >= start
      merge_backwards!(arr, merge_index, buffer_len, buffer_len, buffer_len, &cmp)
      merge_index -= both_merges
    end
  end

  ###################
  # UTILITY METHODS #
  ###################

  def self.insertion_sort!(arr, start, length, &cmp)
    (1...length).map do |i|
      tmp = arr[i]
      j = i - 1
      while j >= start && yield(arr[j], tmp) > 0
        arr[j+1] = arr[j]
        j -= 1
      end
      arr[j+1] = tmp
    end
  end

  # Swap blocks of size k starting at indices a and b
  def self.block_swap!(arr, a, b, k)
    (0...k).map do |i|
      arr[a+i], arr[b+i] = arr[b+i], arr[a+i]
    end
  end

  # Utility method to facilitate rotation. Takes three blocks, [a, b), [b, c), and [c, d), and reverses their order, 
  # using a modified version of the conjoined triple rotation algorithm.
  #
  # It starts by reversing the order of the elements from b to c. It then sets 4 pointers to traverse the array.
  #
  # A ->  <- B        C -> <- D
  # +--------+--------+-------+
  # |  Left  | Middle | Right |
  # +--------+--------+-------+
  #
  # It cycles the elements A -> B -> D -> C -> A, to reverse the outer portions of Left and Right, while moving 
  # the inner portions into place. When one of the subarrays is exhausted, it switched to either A -> B -> D -> A
  # or A -> D -> C -> A. Eventually, two pointers are left:
  #
  #      A ->         <- D
  # +----+---------------+----+
  # | Ri | eL elddiM tgh | ft |
  # +----+---------------+----+
  #
  # It then concludes by reversing the remaining portion
  def self.contrev_rotation!(arr, a, b, c, d)
    e, f = b, c
    ((f-e)/2).times do
      f -= 1
      arr[f], arr[e] = arr[e], arr[f]
      e += 1
    end

    if b - a > d - c
      ((d-c)/2).times do
        b -= 1; d -= 1
        arr[a], arr[b], arr[c], arr[d] = arr[c], arr[a], arr[d], arr[b]
        a += 1; c += 1
      end

      ((b-a)/2).times do
        b -= 1; d -= 1
        arr[a], arr[b], arr[d] = arr[d], arr[a], arr[b]
        a += 1
      end
    else
      ((b-a)/2).times do
        b -= 1; d -= 1
        arr[a], arr[b], arr[c], arr[d] = arr[c], arr[a], arr[d], arr[b]
        a += 1; c += 1
      end

      ((d-c)/2).times do
        d -= 1
        arr[a], arr[c], arr[d] = arr[c], arr[d], arr[a]
        a += 1; c += 1
      end
    end

    ((d-a)/2).times do
      d -= 1
      arr[a], arr[d] = arr[d], arr[a]
      a += 1
    end
  end

  # Rotate the array by swapping blocks of size left and right. Uses one of four algorithms, depending on the sizes.
  #
  #  * If the blocks are equal, do a normal block swap
  #  * If one block is a single element, copy it into a buffer, and slide everything else over
  #  * If the overlap is less than 8 elements, copy it into a buffer, and use the bridge rotation algorithm
  #  * Otherwise, use the conjoined triple rotation algorithm
  #
  # This method has O(1) space complexity, because the number of temporary values can never exceed 8.
  def self.rotate!(arr, start, left, right)
    return if left.zero? || right.zero?

    if left == right
      block_swap!(arr, start, start + left, right)
    elsif left == 1
      temp = arr[start]
      (0...right).map do |i|
        arr[start + i] = arr[start + i + 1]
      end
      arr[start + right] = temp
    elsif right == 1
      temp = arr[start + left]
      left.downto(1) do |i|
        arr[start + i] = arr[start + i - 1]
      end
      arr[start] = temp
    elsif left > right && left - right <= 8
      buffer = arr[start+right...start+left]
      a = start + left
      b = start
      d = start + right

      right.times do
        arr[b], arr[d] = arr[a], arr[b]
        a += 1; b += 1; d += 1
      end

      (0...(left - right)).map do |i|
        arr[d] = buffer[i]
        d += 1
      end
    elsif right > left && right - left <= 8
      buffer = arr[start+left...start+right]
      a = start + left
      b = start + left + right
      d = start + right

      left.times do
        a -= 1; b -= 1; d -= 1
        arr[b], arr[d] = arr[a], arr[b]
      end

      (right - left - 1).downto(0) do |i|
        d -= 1
        arr[d] = buffer[i]
      end
    else
      contrev_rotation!(arr, start, start + left, start + left, start + left + right)
    end
  end

  # Takes three blocks of sizes left, middle, and right, and reverses their order.
  #
  #  * If left == right, do a normal block swap
  #  * If one of the blocks is a single element, pass off to rotate!
  #  * If the middle and at least one other block are 1 element copy them into a buffer and manually shift everything else
  #  * Otherwise, reverse the middle block and pass off to the modified  conjoined triple rotation algorithm
  def self.block_reversal!(arr, start, left, middle, right)
    if left == right
      return block_swap!(arr, start, start + left + middle, right)
    end

    return if middle.zero? && (left.zero? || right.zero?)

    if middle == 1 && left == 1
      buffer = arr[start], arr[start + 1]
      (0...right).map do |i|
        arr[start + i] = arr[start + i + 2]
      end
      arr[start + right], arr[start + right + 1] = buffer[1], buffer[0]
    elsif middle == 1 && right == 1
      buffer = arr[start + left], arr[start + left + 1]
      left.downto(1) do |i|
        arr[start + i + 1] = arr[start + i - 1]
      end
      arr[start], arr[start + 1] = buffer[1], buffer[0]
    else
      contrev_rotation!(arr, start, start + left, start + left + middle, start + left + middle + right)
    end
  end

  # Find the leftmost location where you could insert target, relative to start
  def self.binary_search_left(arr, start, length, target, &cmp)
    arr[start...start+length].bsearch_index { |e| yield(e, target) >= 0 } || length
  end

  # Find the rightmost location where you could insert target, relative to start
  def self.binary_search_right(arr, start, length, target, &cmp)
    arr[start...start+length].bsearch_index { |e| yield(e, target) > 0 } || length
  end

  # Perform a selection sort on a series of equally-sized blocks, based on the first values,
  # using a separate block of keys to break ties and sorting them in parallel
  def self.block_selection_sort!(arr, keys, start, median_key, block_count, block_len, &cmp)
    (1...block_count).map do |i|
      right = left = i - 1

      (i...block_count).map do |j|
        cmp = yield(arr[start + right*block_len], arr[start + j*block_len])
        if cmp > 0 || (cmp == 0 && yield(arr[keys+right], arr[keys+j]) > 0)
          right = j
        end
      end

      if right != left
        block_swap!(arr, start + left*block_len, start + right*block_len, block_len)
        arr[keys+left], arr[keys+right] = arr[keys+right], arr[keys+left]
        if median_key == left
          median_key = right
        elsif median_key == right
          median_key = left
        end
      end
    end

    median_key
  end

  # Merge the blocks A and B, while also shifting them left by buffer_len elements
  #
  # +-----+--------+---------+---------+-----+    +-----+-----------+--------+-----+
  # | ... | Buffer | Block A | Block B | ... | -> | ... | Block A+B | Buffer | ... |
  # +-----+--------+---------+---------+-----+    +-----+-----------+--------+-----+
  def self.merge_forwards!(arr, start, left_len, right_len, buffer, &cmp)
    left = start
    middle = left + left_len
    right = middle + right_len

    if yield(arr[middle-1], arr[middle]) <= 0
      rotate!(arr, left - buffer, buffer, left_len + right_len)
      return
    elsif yield(arr[right-1], arr[left]) < 0
      block_reversal!(arr, left - buffer, buffer, left_len, right_len)
      return
    end

    ptr_a, ptr_b, ptr_dest = left, middle, start - buffer
    while ptr_a < middle && ptr_b < right
      if yield(arr[ptr_a], arr[ptr_b]) <= 0
        arr[ptr_a], arr[ptr_dest] = arr[ptr_dest], arr[ptr_a]
        ptr_a += 1
      else
        arr[ptr_b], arr[ptr_dest] = arr[ptr_dest], arr[ptr_b]
        ptr_b += 1
      end
      ptr_dest += 1
    end

    # If the greatest elements are in block A, the merge will be completed when block B is exhausted. 
    # But if the greatest elements are in block B, we need to rotate the remaining elements into place
    if ptr_b < right
      rotate!(arr, ptr_dest, ptr_b - ptr_dest, right - ptr_b)
    end
  end

  # Merge the blocks A and B, while also shifting them right by buffer_len elements
  #
  # +-----+---------+---------+--------+-----+    +-----+--------+-----------+-----+
  # | ... | Block A | Block B | Buffer | ... | -> | ... | Buffer | Block A+B | ... |
  # +-----+---------+---------+--------+-----+    +-----+--------+-----------+-----+
  def self.merge_backwards!(arr, start, left_len, right_len, buffer, &cmp)
    left = start
    middle = left + left_len
    right = middle + right_len

    if yield(arr[middle-1], arr[middle]) <= 0
      rotate!(arr, left, left_len + right_len, buffer)
      return
    elsif yield(arr[right-1], arr[left]) < 0
      block_reversal!(arr, left, left_len, right_len, buffer)
      return
    end

    ptr_a, ptr_b, ptr_dest = middle - 1, right - 1, right + buffer - 1
    while ptr_a >= left && ptr_b >= middle
      if yield(arr[ptr_a], arr[ptr_b]) <= 0
        arr[ptr_b], arr[ptr_dest] = arr[ptr_dest], arr[ptr_b]
        ptr_b -= 1
      else
        arr[ptr_a], arr[ptr_dest] = arr[ptr_dest], arr[ptr_a]
        ptr_a -= 1
      end
      ptr_dest -= 1
    end

    # If the smallest elements are in block A, the merge will be completed when block B is exhausted. 
    # But if the smallest elements are in block B, we need to rotate the remaining elements into place
    if ptr_a >= left
      rotate!(arr, left, ptr_a - left + 1, ptr_dest - ptr_a)
    end
  end
end
