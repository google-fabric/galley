expect = require 'expect'
_ = require 'lodash'
RSVP = require 'rsvp'

PromiseUtils = require '../lib/lib/promise_utils'

describe 'PromiseUtils', ->
  describe 'promiseEach', ->
    it 'resolves after each promise resolves', ->
      handledValues = {}
      values = ['a', 'b', 'c']

      PromiseUtils.promiseEach values, (val) ->
        new RSVP.Promise (resolve, reject) ->
          process.nextTick ->
            handledValues[val] = true
            resolve()
      .then ->
        expect(handledValues).toEqual
          'a': true
          'b': true
          'c': true

    it 'rejects if a value rejects', ->
      handledValues = {}
      values = ['a', 'b', 'c']

      succeeded = false

      PromiseUtils.promiseEach values, (val) ->
        new RSVP.Promise (resolve, reject) ->
          process.nextTick ->
            return reject('expected') if val == 'b'

            handledValues[val] = true
            resolve()
      .then ->
        succeeded = true
      .catch (err) ->
        throw err unless err == 'expected'
      .then ->
        expect(succeeded).toBe false
        expect(handledValues).toEqual
          'a': true
