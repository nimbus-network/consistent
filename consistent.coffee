_ = require 'underscore'

###
 This library implements consistent objects in JS.  Operations on these
 objects produces an event representing each operation; these objects can
 also have events applied to them in order to receive the same operation.

 The trick is that events can be applied in any order, or even multiple
 times, and always achieve the same result; that is, the operations are
 commutative and idempotent, and thus, eventually consistent.  This
 allows the objects to share state among distributed entities without
 worrying about repeated, out-of-order, or missing messages.
 
 Generally, for two operations f and g,
  f ∘ f = f
  f ∘ g = g ∘ f

 Currently, five data structures are to be implemented.
  - Register:   Simply stores a value, supporting set.
  - List:       A sequence of items, supporting insert and remove.
  - Set:        A set of values, supporting add and remove.
  - Hash:       A map between keys and values, supporting set and delete.
  - Sorted set: A set of values associated with a score.
###

class TagClock
  constructor: (other)->
    @_entries = {}

    if other
      for entry in other
        @_entries[entry] = true
  
  add: ->
    @_entries[Math.random()] = true

  dominates: (other)->
    for entry of other._entries
      if not @_entries[entry]
        return false

    true

  merge: (other)->
    for k of other._entries
      @_entries[k] = true

  copy: ->
    new TagClock Object.keys @_entries

  inspect: ->
    'TagClock([' + Object.keys(@_entries).sort().join(', ') + '])'

class VectorClock
  constructor: (self, other)->
    @_self    = self
    @_entries = {}

    if other
      for key, value of other
        @_entries[key] = value

  add: ->
    @_entries[@_self] = (@_entries[@_self] ? 0) + 1

  dominates: (other)->
    for k, b of other._entries
      a = @_entries[k] ? 0

      if a < b
        return false

    return true
  
  merge: (other)->
    for k, b of other._entries
      @_entries[k] = Math.max b, (@_entries[k] ? 0)
  
  copy: ->
    new VectorClock @_self, @_entries

class Consistent
  constructor: (peer)->
    @_events = []
    @_peer   = peer

  applyEvent: (e)->
    @_events.push e
    @["_#{e.command}"](e)

  applyEvents: (es)->
    @applyEvent(e) for e in es

  events: -> @_events

# Creates a uniformly distributed number in the interval (0, 1)
openRandom = ->
  while true
    n = Math.random()

    if n isnt 0
      return n

class Register extends Consistent
  constructor: (peer)->
    super peer
    @_items = []

  set: (value)->
    newClock = new TagClock()

    for item in @_items
      newClock.merge item.clock

    newClock.add()

    @applyEvent
      command: 'set'
      clock:   newClock
      value:   value

  _set: (e)->
    if @_items.length is 0
      @_items.push
        value: e.value
        clock: e.clock
      return

    keep    = []
    keepNew = true

    for item in @_items
      console.log 'checking', e.clock, 'against', item.clock
      console.log ' 1st dominates 2nd?', e.clock.dominates item.clock
      console.log ' 2nd dominates 1st?', item.clock.dominates e.clock

      if item.clock.dominates e.clock
        keep.push item

      if item.clock.dominates e.clock
        keepNew = false

    if keepNew
      keep.push
        value: e.value
        clock: e.clock

    console.log 'keeping', keep

    @_items = keep

  gets: ->
    console.log 'items', @_items
    item.value for item in @_items

class List extends Consistent
  constructor: (peer)->
    super peer
    @_items   = []
    @_removed = {}

  insert: (value, index)->
    if index > @_items.length or index < 0
      throw new Error "Index out of range."
    
    if @_items.length == 0
      rank = Math.random()
    else if index == @_items.length
      rank = @_items[@_items.length - 1].rank + openRandom()
    else if index == 0
      rank = @_items[0].rank - openRandom()
    else
      first  = @_items[index - 1].rank
      second = @_items[index].rank

      rank = first + (second - first)*openRandom()

    @applyEvent
      command: 'insert'
      peer:    @_peer
      rank:    rank
      value:   value

  push: (value)->
    @insert value, @_items.length

  remove: (index)->
    @applyEvent
      command: 'remove'
      peer:    @_peer
      rank:    @_items[index].rank

  _insert: (e)->
    if @_removed[e.rank]
      return

    item =
      peer: e.peer
      rank: e.rank
      value: e.value

    index = _.sortedIndex @_items, item, 'rank'

    if not (@_items[index]? and @_items[index].rank is e.rank)
      @_items.splice index, 0, item

  _remove: (e)->
    if not @_removed[rank]?
      @_removed[rank] = true

      item =
        peer: e.peer
        rank: e.rank

      index = _.sortedIndex @_items, item, 'rank'

      if @_items[index] and @_items[index].rank is e.rank
        @_items.splice index, 1

  items: ->
    item.value for item in @_items

class Set extends Consistent
  constructor: (peer)->
    super peer
    @_added   = {}
    @_values  = {}
    @_removed = {}

  add: (value)->
    tag = Math.random()

    @applyEvent
      command: 'add'
      tag:     tag
      value:   value

  remove: (value)->
    @applyEvent
      command: 'remove'
      tags:    @_values[value]

  _add: (e)->
    if not @_removed[e.tag]
      @_added[e.tag] = e.value

    if not @_values[e.value]
      @_values[e.value] = []

    @_values[e.value].push e.tag

  _remove: (e)->
    @_removed[tag] = true

    for tag in e.tags
      delete @_added[tag]

class Hash extends Consistent
  constructor: (peer)->
    super peer
    @_values = {}

  set: (key, value)->
    @applyEvent
      command: 'set'
      key:     key
      value:   value

  get: (key)->
    @_values[key].get()

  _set: (e)->
    if not @_values[e.key]?
      @_values[e.key] = new Register @_peer

    @_values[e.key].set e.value

class SortedSet extends Consistent
  constructor: (peer)->
    super peer
    @_items  = []

  add: (score, value)->
    @applyEvent
      command: 'add'
      score:   score
      value:   value
      tag:     Math.random()

  remove: (value)->
    tags = null

    for item, i in @_items
      if item.value == value
        tags = item.tags

    @applyEvent
      command: 'remove'
      tags:    tags

  _add: (e)->
    if @_removed[e.tag]
      return

    tags = null

    for item, i in @_items
      if item.value == e.value
        if item.tags.indexOf(e.tag) != -1
          return

        tags = item.tags
        @_items.splice i, 1
        break

    if not tags?
      tags = []

    tags.push e.tag

    item =
      tags:  tags
      score: e.score
      value: e.value

    index = _.sortedIndex @_items, item, 'score'

    @_items.splice index, 0, item

  _remove: (e)->
    for tag in e.tags
      @_removed[tag] = true

    keep = []

    for item, i in @_items
      for tag in e.tags
        if item.tags.indexOf(tag) == -1
          keep.push item
          break

    @_items = keep

exports.TagClock    = TagClock
exports.VectorClock = VectorClock
exports.Register    = Register
exports.List        = List
exports.Set         = Set
exports.Hash        = Hash
exports.SortedSet   = SortedSet

