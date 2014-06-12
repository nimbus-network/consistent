consistent = require './consistent'
assert     = require 'assert'

describe 'Consistent', ->
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

      y.applyEvents y.events()
      assert.deepEqual y.gets(), ['b', 'a']

