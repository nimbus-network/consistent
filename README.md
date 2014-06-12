Consistency
===========

This module implements eventually consistent data structures in JavaScript.

A consistent data structure is mutated by operations that are idempotent
and commutative; or, in other words,

> *f* &#8728; *f* = *f*
>
> *f* &#8728; *g* = *g* &#8728; *f*

where *f* and *g* are operations, and &#8728; composes functions.  These
properties means that even if a message is received twice or in the wrong
order, the result will be consistent with what is received so far.  The
primary application is in distributed systems; each data structure takes
peername that identifies it to other instances of the structure and
maintains a log of the operations that it has seen.

This module implements five basic data structures and operations:

 - **Register**, a container containg a single value that can be set.
 - **List**, an ordered sequence of values that can be inserted or removed.
 - **Set**, an unordered collection of unique values that can be added or
   removed.
 - **Hash**, a hash table with keys that can be set.
 - **Sorted set**, a collection of unique values with ordered scores.

The choice of the basic data types is based on Redis.

### Registers ###

A register contains a single value.  It can be used as follows.

    var a = new Register('alice'),
        b = new Register('bob');

    a.set(1);

    console.log(a.get()); // [ 1 ]

    b.set(2);

    console.log(b.get()); // [ 2 ]

    // Send Alice's events to Bob, and vice-versa.
    a.applyEvents(b.events());
    b.applyEvents(a.events());

    // Alice and Bob now have two possible values, because they set their
    // registers without knowledge of the other register's value.
    console.log(a.get()); // [ 1, 2 ]
    console.log(b.get()); // [ 1, 2 ]

    a.set(1);

    // There is now just one possible value, because Alice was aware of
    // Bob's choice, and can thus dominate it.
    console.log(a.get()); // [ 1 ]

    b.applyEvents(a.events());

    console.log(b.get()); // [ 1 ]

#### Implementation of Register ####

To implement the register, we need to record what values we have previously
seen.  For instance, if we start with an empty register, there are no
previous values, so we just place the value directly.  Thus our operation
can be encoded as

    {command: 'set', value: 1, dominates: []}

Leaving the state of the register as

    a1 = [{value: 1, dominates: []}]

Now if we set the value to `2`, we have to state that we're
dominating `1`.

    {command: 'set', value: 2, dominates: [1]}

When we apply this operation to our register, we remove all the values that
this operation dominates, namely, `1`, and add the new value if none of the
present values dominate the one we're adding:

    a2 = [{value: 2, dominates: [1]}]

However, now there's an issue; we can't ever set the register to 1 again,
because it's dominated.  Thus, we add a random tag to each operation.  We'll
use `Math.random()` (I'll only write the first few digits though).

Our original operation where we set to the value to 1 would look like

    {command: 'set', value: 1, tag: 0.018, dominates: []}

The second operation would then dominate this tag instead of the value itself:

    {command: 'set', value: 2, tag: 0.172, dominates: [0.018]}

Now if we want to set the register to 1 again, we can do

    {command: 'set', value: 1, tag: 0.821, dominates: [0.018, 0.172]}

The state of Alice's register is now

    [{value: 1, tag: 0.821, dominates: [0.018, 0.172]}]

Let's see what happens if Bob sets a value and merges his state with Alice's.

Bob sets his value to 3 with the operation
    
    {command: 'set', value: 3, tag: 0.051, dominateS: []}

Now his register looks like this:

    b1 = [{value: 3, tag: 0.051, dominates: []}]

If Alice applies Bob's operation to her own register, she gets

    [{value: 1, tag: 0.821, dominates: [0.018, 0.172]},
     {value: 3, tag: 0.051, dominates: []}]

There are now two values in the register because Bob's value didn't dominate
Alice's, and Alice's value didn't dominate Bob's.  However, if Alice now sets
the register to 4, it would dominate both her and Bob's values.

    {command: 'set', value: 4, dominates: [0.018, 0.172, 0.821, 0.051]}

#### Optimizations ####

However, the `dominates` field will undoubtedly become quite large after some
time; since it's a 64-bit double, it'll use 8 bytes per previously overwritten
value.  In some cases this could become very expensive.

However, there is one assumption we're not relying on: Alice and Bob always see
all of their own events.  Let's rewrite the previous operations, but instead of
a random tag, the tag will be an incrementing count paired with the name of the
peer.

The operations would become

    {command: 'set', value: 1, tag: 'alice:1', dominates: []}
    {command: 'set', value: 2, tag: 'alice:2', dominates: ['alice:1']}
    {command: 'set', value: 1, tag: 'alice:3', dominates: ['alice:1', 'alice:2']}
    {command: 'set', value: 3, tag: 'bob:1', dominates: []}
    {command: 'set', value: 4, tag: 'alice:4', dominates: ['alice:1', 'alice:2', 'alice:3', 'bob:1']}

There's clearly a missed opportunity here; insetad of listing out every tag
that's dominated, we can list the greatest tag from that peer we've seen, since
we can assume a peer has seen all of their own tags so far.  It might look like
this

    {command: 'set', value: 1, dominates: {alice: 1}}
    {command: 'set', value: 2, dominates: {alice: 2}}
    {command: 'set', value: 1, dominates: {alice: 3}}
    {command: 'set', value: 3, dominates: {bob: 1}}
    {command: 'set', value: 4, dominates: {alice: 4, bob: 1}}

Coincidentally, we've reinvented [vector clocks](http://en.wikipedia.org/wiki/Vector_clock).

### Lists ###

Lists are more complex, as they must maintain the relative order
between elements.

Using the same tag solution as the register, we could have each element have a
set of tags of the elements that go before and after this item.

Starting with an empty list,

    []

Alice might insert 1 at position 0.  There is nothing before or after it at that position.

    [{value: 1, before: {alice: 1}, after: {alice: 1}}]

If she inserts again at position 0, it'd be before the element we just inserted.

    [{value: 2, before: {alice: 1}, after: {alice: 2}}, {value: 1, before: {alice: 1}, after: {alice: 1}}]

Now let's say Bob and Alice are synchronized, and both try to insert an element
into the middle with the operations.

Alice would use the operation

    {command: 'insert', value: 3, before: {alice: 1, bob: 1}, after: {alice: 1, bob: 1}}

And Bob would use

    {command: 'insert', value: 4, before: {alice: 2}, after: {alice: 2}}

However, there might be a better way than clocks.  We primarily need tags that
are orderable; thus, we'll go back to the original method of using random tags,
but construct them in a way that lets us easily order the elements.

We'll give each element a rank, which is just a unique float-point number.
Assume that *x* is a random number in the interval (0, 1).  An element placed
in an empty list will have rank *x*.  To place an element at the end of the list,
we take the rank of the last element and add *x* to it.  Similarly, to place the
element at the beginning of the list, we take the rank of the first element and
subtract *x* from it.  Finally, to place an element between two other elements,
where *a* is the rank of the one before and *b* the rank of the one after,
we set the rank to a + (b - a)&times;*x* to place it between them.

Now starting with an empty list,

    []

If Alice inserts 1, we get

   [{value: 1, rank: 0.964}]

Inserting 2 at the end gives
  
  [{value: 1, rank: 0.964}, {value: 2, rank: 1.119}]

Inserting 3 at the beginning gives

  [{value: 3, rank: 0.624}, {value: 1, rank: 0.964}, {value: 2, rank: 1.119}]

Finally, inserting 4 between the second and third elements gives
  
  [{value: 3, rank: 0.624}, {value: 1, rank: 0.964}, {value: 4, rank: 1.108}, {value: 2, rank: 1.119}]

No matter the order the messages are received, these will end up in the correct order.

