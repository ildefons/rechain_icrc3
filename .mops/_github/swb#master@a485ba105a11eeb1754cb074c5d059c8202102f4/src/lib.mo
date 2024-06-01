/// SlidingWindowBuffer
///
/// Copyright: 2023 MR Research AG
/// Main author: Timo Hanke (timohanke)
/// Contributors: Andy Gura (AndyGura), Andrii Stepanov (AStepanov25)

import Prim "mo:⛔";
import { bitcountLeadingZero = leadingZeros; fromNat = Nat32; toNat = Nat } "mo:base/Nat32";
import Array "mo:base/Array";
import Option "mo:base/Option";

module {
  // Deletable vector
  //
  // This data structure starts with a small subset of the Vector data structure
  // from https://mops.one/vector. Only the code for `add`, `getOpt` and `size`
  // is present here.
  //
  // Then we add a `delete` function which deleted from the beginning. It does
  // so not by shrinking the Vector but simply by overwriting the deleted
  // entries with `null`.
  //
  // Deletion will leave overhead that cannot be freed. But this problem will be
  // mitigated at the next level in the code that uses this Vector (in the
  // SlidingWindowBuffer class).
  type VectorStableData<X> = {
    data_blocks : [var [var ?X]];
    i_block : Nat;
    i_element : Nat;
    start_ : Nat;
  };

  class Vector<X>() {
    var data_blocks : [var [var ?X]] = [var [var]];
    var i_block : Nat = 1;
    var i_element : Nat = 0;
    var start_ : Nat = 0;

    public func share() : VectorStableData<X> = {
      data_blocks = data_blocks;
      i_block = i_block;
      i_element = i_element;
      start_ = start_;
    };

    public func unshare(data : VectorStableData<X>) {
      data_blocks := data.data_blocks;
      i_block := data.i_block;
      i_element := data.i_element;
      start_ := data.start_;
    };

    public func size<X>() : Nat {
      let d = Nat32(i_block);
      let i = Nat32(i_element);
      let lz = leadingZeros(d / 3);
      Nat((d -% (1 <>> lz)) <>> lz +% i);
    };

    func data_block_size(i_block : Nat) : Nat {
      Nat(1 <>> leadingZeros(Nat32(i_block) / 3));
    };

    func new_index_block_length(i_block : Nat32) : Nat {
      if (i_block <= 1) 2 else {
        let s = 30 - leadingZeros(i_block);
        Nat(((i_block >> s) +% 1) << s);
      };
    };

    func grow_index_block_if_needed() {
      if (data_blocks.size() == i_block) {
        let new_blocks = Array.init<[var ?X]>(new_index_block_length(Nat32(i_block)), [var]);
        var i = 0;
        while (i < i_block) {
          new_blocks[i] := data_blocks[i];
          i += 1;
        };
        data_blocks := new_blocks;
      };
    };

    public func add(element : X) : Nat {
      if (i_element == 0) {
        grow_index_block_if_needed();

        if (data_blocks[i_block].size() == 0) {
          data_blocks[i_block] := Array.init<?X>(
            data_block_size(i_block),
            null,
          );
        };
      };

      let last_data_block = data_blocks[i_block];

      last_data_block[i_element] := ?element;

      i_element += 1;
      if (i_element == last_data_block.size()) {
        i_element := 0;
        i_block += 1;
      };

      return size() - 1;
    };

    func locate(index : Nat) : (Nat, Nat) {
      let i = Nat32(index);
      let lz = leadingZeros(i);
      let lz2 = lz >> 1;
      if (lz & 1 == 0) {
        (Nat(((i << lz2) >> 16) ^ (0x10000 >> lz2)), Nat(i & (0xFFFF >> lz2)));
      } else {
        (Nat(((i << lz2) >> 15) ^ (0x18000 >> lz2)), Nat(i & (0x7FFF >> lz2)));
      };
    };

    public func getOpt(index : Nat) : ?X {
      let (a, b) = locate(index);
      if (a < i_block or i_element != 0 and a == i_block) {
        data_blocks[a][b];
      } else {
        null;
      };
    };

    public func delete(n : Nat) = deleteTo(start_ + n);

    // delete up to but excluding position `end`
    // if end <= start_ then nothing gets deleted
    // TODO: This can be made more sophisticated, we can improve:
    // * time: avoid calling locate, increment (block, element) directly
    // * memory: delete the datablocks that have become empty
    public func deleteTo(end : Nat) {
      if (end > size()) Prim.trap("index out of bounds in deleteTo");
      if (end <= start_) return;
      var pos = start_;
      while (pos < end) {
        let (a, b) = locate(pos);
        data_blocks[a][b] := null;
        pos += 1;
      };
      start_ := end;
    };

    // number of non-deleted entries
    public func len() : Nat = size() - start_;

    // number of deleted entries
    public func start() : Nat = start_;
  };

  /// Stable data for a sliding window buffer
  public type StableData<X> = {
    old : ?VectorStableData<X>;
    new : VectorStableData<X>;
    i_old : Nat;
    i_new : Nat;
  };

  /// Sliding window buffer
  ///
  /// A linear buffer with random access where we can add at end and delete from
  /// the beginning.  Elements remain at their original position, despite
  /// deletion, hence the data structure becomes in fact a sliding window into an
  /// ever-growing buffer.
  ///
  /// This data structure consists of a pair of Vectors called `old` and `new`.
  /// We always add to `new`.  While `old` is empty we delete from `new` but only
  /// until the waste in `new` exceeds sqrt(n). When `new` has >sqrt(n) waste
  /// then we rename `new` to `old` and create a fresh empty `new`. Now deletions
  /// happen from old, until old is empty. Then `old` is discarded and deletions
  /// happen from `new` again until the waste in `new` exceeds sqrt(n). Then the
  /// shift starts all over again. Etc.
  ///
  /// Only the waste in `new` is limited to sqrt(n). The waste in `old` is not limited.
  /// Hence, the largest waste occurs if we do n additions first, then n deletions.
  public class SlidingWindowBuffer<X>() {
    var old : ?Vector<X> = null;
    var new : Vector<X> = Vector<X>();
    var i_old = 0; // offset of old
    var i_new = 0; // offset of new

    public func share() : StableData<X> = {
      old = Option.map(old, func(o : Vector<X>) : VectorStableData<X> = o.share());
      new = new.share();
      i_old = i_old;
      i_new = i_new;
    };

    public func unshare(data : StableData<X>) {
      switch (data.old) {
        case (null) {};
        case (?o) {
          let v = Vector<X>();
          v.unshare(o);
          old := ?v;
        };
      };
      new.unshare(data.new);
      i_old := data.i_old;
      i_new := data.i_new;
    };

    /// Add an element to the end
    public func add(x : X) : Nat {
      new.add(x) + i_new;
    };

    /// Random access based on absolute (ever-growing) index.
    /// Returns `null` if the index falls outside the sliding window on either end.
    public func getOpt(i : Nat) : ?X {
      if (i >= i_new) {
        new.getOpt(i - i_new : Nat);
      } else if (i >= i_old) {
        let ?vec = old else Prim.trap("old is null in Buffer");
        vec.getOpt(i - i_old : Nat);
      } else null;
    };

    func rotateIfNeeded() {
      let size = new.size();
      let s = Nat32(size);
      let d = Nat32(new.start());
      let bits = 32 - leadingZeros(s);
      let limit = s >> (bits >> 1);
      if (d > limit) {
        old := ?new;
        i_old := i_new;
        new := Vector<X>();
        i_new += size;
      };
    };

    /// Delete n elements from the beginning.
    /// Traps if less than n elements are available.
    public func delete(n : Nat) = deleteTo(start() + n);

    public func deleteTo(end_ : Nat) {
      if (end_ > end()) Prim.trap("index out of bounds in SlidingWindowBuffer.deleteTo");
      if (end_ >= i_new) {
        new.deleteTo(end_ - i_new : Nat);
        rotateIfNeeded();
        // free old is possible
        if (end_ >= i_new) {
          old := null;
          i_old := i_new;
        };
      } else if (end_ >= i_old) {
        let ?vec = old else Prim.trap("cannot happen");
        vec.deleteTo(end_ - i_old : Nat);
      };
    };

    /// The starting position of the sliding window.
    /// If the window is non-empty then this equals the index of the first
    /// element in the window.
    public func start() : Nat = switch (old) {
      case (?vec) { i_old + vec.start() };
      case (null) { i_new + new.start() };
    };

    /// The ending position (exclusive) of the sliding window
    /// = the index of the next element that would be added
    /// = the total number of additions that have ever been made
    /// = the size of the whole virtual buffer including deletions
    public func end() : Nat = i_new + new.size();

    /// The length of the window, i.e. the number of elements that are actually
    /// available to get.
    public func len() : Nat = end() - start();
  };
};
