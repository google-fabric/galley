var PromiseUtils, RSVP, _, expect;

expect = require('expect');

_ = require('lodash');

RSVP = require('rsvp');

PromiseUtils = require('../lib/lib/promise_utils');

describe('PromiseUtils', function() {
  return describe('promiseEach', function() {
    it('resolves after each promise resolves', function() {
      var handledValues, values;
      handledValues = {};
      values = ['a', 'b', 'c'];
      return PromiseUtils.promiseEach(values, function(val) {
        return new RSVP.Promise(function(resolve, reject) {
          return process.nextTick(function() {
            handledValues[val] = true;
            return resolve();
          });
        });
      }).then(function() {
        return expect(handledValues).toEqual({
          'a': true,
          'b': true,
          'c': true
        });
      });
    });
    return it('rejects if a value rejects', function() {
      var handledValues, succeeded, values;
      handledValues = {};
      values = ['a', 'b', 'c'];
      succeeded = false;
      return PromiseUtils.promiseEach(values, function(val) {
        return new RSVP.Promise(function(resolve, reject) {
          return process.nextTick(function() {
            if (val === 'b') {
              return reject('expected');
            }
            handledValues[val] = true;
            return resolve();
          });
        });
      }).then(function() {
        return succeeded = true;
      })["catch"](function(err) {
        if (err !== 'expected') {
          throw err;
        }
      }).then(function() {
        expect(succeeded).toBe(false);
        return expect(handledValues).toEqual({
          'a': true
        });
      });
    });
  });
});
