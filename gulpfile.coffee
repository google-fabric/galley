gulp = require 'gulp'
$ = require('gulp-load-plugins')()
fs = require 'fs'
mocha = require 'gulp-mocha'
mochaTeamcityReporter = require 'mocha-teamcity-reporter'
shell = require 'gulp-shell'
runSequence = require 'run-sequence'
semver = require 'semver'


config =
  build: require './config/build.coffee'

alertError = $.notify.onError (error) ->
  message = error?.stack or error?.message or error?.toString() or 'Something went wrong'
  "Error: #{ message }"

gulp.task 'clean', (cb) ->
  fs = require 'fs'
  dirs = [config.build.build_dir, config.build.dest, config.build.spec_dest, config.build.acceptance_dest]
  glob = []

  for dir in dirs
    fs.mkdirSync dir unless fs.existsSync dir
    glob.push "#{ dir }/**", "!#{ dir }"

  require('del') glob, cb

gulp.task 'compile', ->
  gulp.src([
    "#{ config.build.src }/**/*.coffee"
  ])
    .pipe($.plumber errorHandler: alertError)
    .pipe($.changed config.build.dest)
    .pipe($.coffee bare: true)
    .pipe(gulp.dest config.build.dest)

  gulp.src([
    "#{ config.build.spec_src }/**/*.coffee"
  ])
    .pipe($.plumber errorHandler: alertError)
    .pipe($.changed config.build.dest)
    .pipe($.coffee bare: true)
    .pipe(gulp.dest config.build.spec_dest)

  gulp.src([
    "#{ config.build.acceptance_src }/*.coffee"
  ])
    .pipe($.plumber errorHandler: alertError)
    .pipe($.changed config.build.dest)
    .pipe($.coffee bare: true)
    .pipe(gulp.dest config.build.acceptance_dest)

gulp.task 'build', (cb) ->
  runSequence 'clean', ['compile'], cb

gulp.task 'watch', (cb) ->
  gulp.watch [
    "#{ config.build.src }/**/*.coffee"
    "#{ config.build.spec_src }/**/*.coffee"
    "#{ config.build.acceptance_src }/**/*.coffee"
  ], ['compile']


  cb()

mochaArgs = ->
  args = {}

  if process.env['USE_MOCHA_TEAMCITY_REPORTER']
    args.reporter = mochaTeamcityReporter

  args

gulp.task 'test', ->
  gulp.src("#{config.build.spec_dest}/**/*.js")
    .pipe(mocha(mochaArgs()))

gulp.task 'acceptance:build', shell.task [
  './acceptance/dockerfiles/build.sh'
]

gulp.task 'acceptance:test', ->
  gulp.src("#{config.build.acceptance_dest}/**/*.js")
    .pipe(mocha(mochaArgs()))

gulp.task 'acceptance', (cb) ->
  runSequence 'acceptance:build', 'acceptance:test', cb

# ------------------------------------------------------------------------------
# Bump Version
# ------------------------------------------------------------------------------
do ->
  bumpVersion = (type) ->
    (cb) ->
      pkg = JSON.parse fs.readFileSync('./package.json', 'utf8')
      pkg.version = pkg.version?.replace /[^\.\d]/g, ''

      if type in ['patch', 'major', 'minor']
        pkg.version = semver.inc pkg.version, type
      else
        pkg.version = [pkg.version, type].join ''

      fs.writeFileSync 'package.json', JSON.stringify(pkg, null, 2) + '\n'
      cb()

  gulp.task 'bump', bumpVersion 'alpha'
  gulp.task 'bump:local', bumpVersion 'alpha'
  gulp.task 'bump:patch', bumpVersion 'patch'
  gulp.task 'bump:minor', bumpVersion 'minor'
  gulp.task 'bump:major', bumpVersion 'major'

gulp.task 'default', (cb) ->
  runSequence 'build', 'watch', cb
