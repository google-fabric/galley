## Overview
Galley is a tool for managing docker dependencies.
Docker makes it easy to connect two containers together, through '--links', but managing
what services your infrastructure uses, and how those services are connected together can
be challenging with docker alone. Galley bridges that gap.

Galley lets you think about your code in terms of 'services' rather than just containers.
A service is simply a single container that depends on a fixed set of other containers.

When you start, create, or run a service, galley knows to make sure that its linked dependencies are
running too.

Using galley is a two step process:
1. Write a Galleyfile defining your applications, dependencies, and environments, and point galley at the file.
  - Galleyfiles are executable JS (or coffeescript), so you can treat your Galleyfile like code: DRY, version controlled, and composable.

1. Run `galley run your-application.environment`
  - Galley respects familiar docker syntax
  - Supports volume mapping, exposing ports, attaching and detaching running containers, and setting environment varialbes
  - Can map local change into the container FAST, using a special rsync container. Invaluable for doing development with docker on a Mac without paying the NFS performance cost.

Use `galley pull your-application.environment` to bring all the images your application depends to to their latest version.

Use `galley cleanup` to remove dangling images, and remove stopped, non-stateful containers (preserves your databases!)


##### You might want to use galley when...
Galley is awesome for putting together an environment for doing your day-to-day development work. Galley helps you keep your test and development
environments isolated, while allowing you to effectively emulate production. It helps you manage running containers, providing shortcuts for starting, stopping, and removing just the containers you want. Never accidentally destroy your database again!

You might set up galley when:
 - You want to move your development environment from Vagrant to Docker
 - You want to run your integration tests locally, against a wide range of services, each with their own dependencies
 - You have many different applications, each with shared dependencies

## Installation

```
$ npm install -g 'git+ssh://git@github.com:crashlytics/galley#distribution'
```

## Getting Started

After you've installed Galley, you'll need to set up a Galleyfile. Your Galleyfile is Javascript that will be executed as galley is starting up your containers.

Here's an example `Galleyfile.coffee`

You probably want to save your Galleyfile somewhere in your version control system, likely near your "base" Docker images. The file must be named `Galleyfile.*`.


```coffeescript
devTestEnv =
  'dev': 'development'
  'test': 'test'

RAILS_ENV = devTestEnv

module.exports =
  # The base configuration for a Galleyfile, sets up your docker registry, and
  # other global galley configs
  CONFIG:
    registry: 'docker.crash.io'
    rsync:
      image: 'docker.crash.io/rsync'
      module: 'root'

  # Galley needs to know about every service, so some entries may be empty
  'srv-config': {}

  # the ports key tells galley which exposed ports to map out, in which environment.
  'beanstalk':
    ports:
      'dev': ['11300:11300']

  # Stateful instructs galley to bias to leaving these containers around to preserve the state
  # of your databases.
  'mysql':
    stateful: true

  # If the links (or ports, etc) are the same in every environment, you can omit the environment
  # specification and galley knows that just means "all"
  #
  # The env key allows you to set environment variables in the container, e.g. for parametrizing
  # into dev and test.
  #
  # The source key tells galley the working directory in your docker container, so that it can map
  # a local directory into the container and run your modified source (or binary)
  'small-rails-app':
    links: ['mysql']
    env: RAILS_ENV
    source: '/srv/small-rails/current'


  # If your application has different dependencies in different enviroments, you can capture that explicitly with links.
  # Links will always resolve recursively, so in the test.cucumber environment the small-rails-app and its dependencies will start before large-rails-app starts
  #
  # The volumesFrom key allows you to map in a volume container. Great for managing config files!
  'large-rails-app':
    links:
      'dev': ['mysql', 'beanstalk']
      'test': ['mysql']
      'test.cucumber': ['mysql', 'beanstalk', 'small-rails-app']
    ports:
      'dev': ['3000:3000']
    env: RAILS_ENV
    source: '/srv/large-rails/current'
    volumesFrom: ['srv-config']
```

Once you have a Galleyfile, point galley at that file by running
```
galley config set configDir /path/to/folder/with/Galleyfile
```

Test your new galley set up by running
```
  galley run large-rails-app.dev
```

And confirming that your application is now serving traffic from the mapped port.

## Tech Details
 - galley is written in coffeescript with node.js
 - built with gulp
 - tested with mocha


