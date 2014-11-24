expect = require 'expect'
_ = require 'lodash'

Run = require '../lib/commands/run'

describe 'parseArgs', ->
  describe 'addons option support', ->
    describe 'with a single value', ->
      TEST_ARGS = '--configDir acceptance -a database --entrypoint ls application.foo'.split(' ')

      it 'should generate addon options with an array with one value', ->
        addons = Run.parseArgs(TEST_ARGS).options.add
        expect(addons).toEqual(['database'])

    describe 'with a multiple values through multiple params', ->
      TEST_ARGS = '--configDir acceptance -a database -a config --entrypoint ls application.foo'.split(' ')

      it 'should generate addon options with an array with multiple values', ->
        addons = Run.parseArgs(TEST_ARGS).options.add
        expect(addons).toEqual(['database', 'config'])

    describe 'with a multiple values through a single delimited param', ->
      TEST_ARGS = '--configDir acceptance -a database,config --entrypoint ls application.foo'.split(' ')

      it 'should generate addon options with an array with multiple values', ->
        addons = Run.parseArgs(TEST_ARGS).options.add
        expect(addons).toEqual(['database', 'config'])

    describe 'with a trailing comma', ->
      TEST_ARGS = '--configDir acceptance -a database, --entrypoint ls application.foo'.split(' ')

      it 'should generate addon options that do not include an empty string', ->
        addons = Run.parseArgs(TEST_ARGS).options.add
        expect(addons).toEqual(['database'])

    describe 'with a mix of delimited and non-delimited params', ->
      TEST_ARGS = '--configDir acceptance -a database,config -a other --entrypoint ls application.foo'.split(' ')

      it 'should generate addon options with an array with multiple values', ->
        addons = Run.parseArgs(TEST_ARGS).options.add
        expect(addons).toEqual(['database', 'config', 'other'])

    describe 'with the long param name', ->
      TEST_ARGS = '--configDir acceptance --add database,config --entrypoint ls application.foo'.split(' ')

      it 'should generate the addon options as usual', ->
        addons = Run.parseArgs(TEST_ARGS).options.add
        expect(addons).toEqual(['database', 'config'])

    describe 'with the parameter not specified', ->
      TEST_ARGS = '--configDir acceptance --entrypoint ls application.foo'.split(' ')

      it 'should generate an empty array of addons', ->
        addons = Run.parseArgs(TEST_ARGS).options.add
        expect(addons).toEqual([])
