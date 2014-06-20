consistent = require './consistent'
assert     = require 'assert'

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

