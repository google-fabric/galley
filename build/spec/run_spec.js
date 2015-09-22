var Run, _, expect;

expect = require('expect');

_ = require('lodash');

Run = require('../lib/commands/run');

describe('parseArgs', function() {
  return describe('addons option support', function() {
    describe('with a single value', function() {
      var TEST_ARGS;
      TEST_ARGS = '--configDir acceptance -a database --entrypoint ls application.foo'.split(' ');
      return it('should generate addon options with an array with one value', function() {
        var addons;
        addons = Run.parseArgs(TEST_ARGS).options.add;
        return expect(addons).toEqual(['database']);
      });
    });
    describe('with a multiple values through multiple params', function() {
      var TEST_ARGS;
      TEST_ARGS = '--configDir acceptance -a database -a config --entrypoint ls application.foo'.split(' ');
      return it('should generate addon options with an array with multiple values', function() {
        var addons;
        addons = Run.parseArgs(TEST_ARGS).options.add;
        return expect(addons).toEqual(['database', 'config']);
      });
    });
    describe('with a multiple values through a single delimited param', function() {
      var TEST_ARGS;
      TEST_ARGS = '--configDir acceptance -a database,config --entrypoint ls application.foo'.split(' ');
      return it('should generate addon options with an array with multiple values', function() {
        var addons;
        addons = Run.parseArgs(TEST_ARGS).options.add;
        return expect(addons).toEqual(['database', 'config']);
      });
    });
    describe('with a trailing comma', function() {
      var TEST_ARGS;
      TEST_ARGS = '--configDir acceptance -a database, --entrypoint ls application.foo'.split(' ');
      return it('should generate addon options that do not include an empty string', function() {
        var addons;
        addons = Run.parseArgs(TEST_ARGS).options.add;
        return expect(addons).toEqual(['database']);
      });
    });
    describe('with a mix of delimited and non-delimited params', function() {
      var TEST_ARGS;
      TEST_ARGS = '--configDir acceptance -a database,config -a other --entrypoint ls application.foo'.split(' ');
      return it('should generate addon options with an array with multiple values', function() {
        var addons;
        addons = Run.parseArgs(TEST_ARGS).options.add;
        return expect(addons).toEqual(['database', 'config', 'other']);
      });
    });
    describe('with the long param name', function() {
      var TEST_ARGS;
      TEST_ARGS = '--configDir acceptance --add database,config --entrypoint ls application.foo'.split(' ');
      return it('should generate the addon options as usual', function() {
        var addons;
        addons = Run.parseArgs(TEST_ARGS).options.add;
        return expect(addons).toEqual(['database', 'config']);
      });
    });
    return describe('with the parameter not specified', function() {
      var TEST_ARGS;
      TEST_ARGS = '--configDir acceptance --entrypoint ls application.foo'.split(' ');
      return it('should generate an empty array of addons', function() {
        var addons;
        addons = Run.parseArgs(TEST_ARGS).options.add;
        return expect(addons).toEqual([]);
      });
    });
  });
});
