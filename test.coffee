consistent = require './consistent'
assert     = require 'assert'

# Test the dominating relationship of a clock.
testDominates = (x, y)->
  assert x.dominates y
  assert y.dominates x

  x.add()

  assert x.dominates y
  assert not y.dominates x

  y.add()

  assert not x.dominates y
  assert not y.dominates x

  z = x.copy()

  assert x.dominates z
  assert z.dominates x
  assert not z.dominates y
  assert not y.dominates z

  z.add()

  assert z.dominates x
  assert not x.dominates z
  assert not z.dominates y
  assert not y.dominates z

describe 'Consistent', ->
  describe 'TagClock', ->
    it 'can dominate other TagClocks', ->
      x = new consistent.TagClock()
      y = new consistent.TagClock()

      testDominates x, y
      
  describe 'VectorClock', ->
    it 'can dominates other VectorClocks', ->
      x = new consistent.VectorClock 'x'
      y = new consistent.VectorClock 'y'

      testDominates x, y

  describe 'Register', ->
    it 'can store values and retrieve them', ->
      x = new consistent.Register()

      assert.deepEqual x.gets(), []

      x.set 'a'
      assert.deepEqual x.gets(), ['a']

      x.set 'b'
      assert.deepEqual x.gets(), ['b']
    
    it 'is consistent', ->
      x = new consistent.Register 'x'
      y = new consistent.Register 'y'

      x.set 'a'
      y.set 'b'

      assert.deepEqual x.gets(), ['a']
      assert.deepEqual y.gets(), ['b']

      x.applyEvents x.events()
      assert.deepEqual x.gets(), ['a']

      x.applyEvents y.events()
      assert.deepEqual x.gets(), ['a', 'b']

      y.applyEvents x.events()
      assert.deepEqual y.gets(), ['a', 'b']

      y.set 'c'
      y.applyEvents x.events()
      assert.deepEqual y.gets(), ['c']
  
  describe 'List', ->
    it 'can insert values and retrieve them', ->
      x = new consistent.List()

      x.insert 'b', 0
      x.insert 'c', 1
      x.push 'e'
      x.insert 'a', 0
      x.insert 'd', 3

      assert.deepEqual x.items(), ['a', 'b', 'c', 'd', 'e']

      x.remove 1
      x.remove 2

      assert.deepEqual x.items(), ['a', 'c', 'e']

    it 'merges correctly', ->
      x = new consistent.List()
      y = new consistent.List()
      
      x.push 'a'
      x.push 'b'

      y.push 'c'
      y.push 'd'

      assert.deepEqual x.items(), ['a', 'b']
      assert.deepEqual y.items(), ['c', 'd']

      x.applyEvents x.events()
      assert.deepEqual x.items(), ['a', 'b']

      x.applyEvents y.events()
      assert x.items().indexOf('a') < x.items().indexOf('b')
      assert x.items().indexOf('c') < x.items().indexOf('d')
      
      y.applyEvents y.events()
      assert.deepEqual y.items(), ['c', 'd']

      y.applyEvents x.events()
      assert y.items().indexOf('a') < y.items().indexOf('b')
      assert y.items().indexOf('c') < y.items().indexOf('d')

      assert.deepEqual x.items(), y.items()

      x.push 'e'
      x.push 'f'

      y.applyEvents x.events()
      assert.equal y.items().indexOf('e'), 4
      assert.equal y.items().indexOf('f'), 5

      y.insert 'n', 0
      x.insert 'n', 0

      x.applyEvents y.events()
      y.applyEvents x.events()

      assert.equal x.items()[0], 'n'
      assert.equal x.items()[1], 'n'
      assert.equal y.items()[0], 'n'
      assert.equal y.items()[1], 'n'

      x.remove 0

      x.applyEvents x.events()
      assert.equal x.items()[0], 'n'
      assert.notEqual x.items()[1], 'n'

      y.applyEvents x.events()
      assert.equal y.items()[0], 'n'
      assert.notEqual y.items()[1], 'n'

