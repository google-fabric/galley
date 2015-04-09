## Overview

Galley is a command-line tool for orchestrating Docker containers in local development and test environments. Galley
automatically starts a container’s dependencies and connects it to them with Links and VolumesFrom mappings. Use
Galley to start up a web server that connects to a database. Then use it to start up a web server, its database, an 
intermediate data service, its database, some queues, worker processes, and the monitoring server they all connect 
to.

### What makes Galley different?

Galley was built to match our development process: multiple teams sharing a dozen or more services across a
variety of source code repositories. What is under active development by one team might just be a dependency to
another, so Galley gives engineers the flexibility to start the service or services they’re working with using
local source changes, while using the Docker repository’s pre-built images for any depenencies.

Galley keeps service dependencies in a central “Galleyfile” configuration so that you can always start up any 
service in your system, along with any necessary transitive dependencies.

### Features

 - Run Docker containers, linking them to their dependencies
 - Runtime control over whether to mount local source code into containers
 - Custom environments to easily run development and test containers side-by-side in isolation
 - “Addons” to define optional dependencies or configuration for services
 - Automatically re-uses running containers to support developing on multiple services simultaneously
 - Prevents “stateful” containers like databases from being wiped through recreates
 - JavaScript-based configuration allows for higher-order service definitions

Galley also has special support for running under a VM, such as when using boot2docker on Mac OS X:

 - Built-in `rsync` support for massively-improved disk performance when mapping in source code
 - Port forwarding to let other machines or mobile devices connect to containers in the VM

And, for continuous integration machines:

 - A `--repairSourceOwnership` flag keeps the container from generating files that only root can delete


## Galley concepts

Before using Galley, you define a set of **services** in a central **Galleyfile**. These definitions specify what
Docker options to use to create a container for that service (image, links, volumes, *&tc.*).

When you use `galley run <service>.<env>`, you provide a **primary service** that you want to interact with, and the
**environment** to run it in. Environments are used in service definitions to vary the configuration, for example to
specify different dependencies between “dev” and “test” modes.

## Commands

### `run`

**Example:** `galley run www.dev`

Starts up the given service, using the environment both to name containers and to affect the service configuration.
Dependencies, either `links` or `volumesFrom`, will be started up first and recursively. Containers will be named
“<service>.<env>”.

Galley will *always* recreate the container for the named (“primary”) service. For dependencies, Galley will look
for existing containers that match the “<service>.<env>” naming pattern, starting them if necessary. It will
recreate them if:

 - their source image doesn’t match the current image for their image name (*e.g.* if an image was built or pulled
   since first starting the container)
 - their current `Links` don’t include everything in the current configuration (typically because a container they 
   depend upon has been recreated, but sometimes because an addon changes the configuration)

Nevertheless, if a service is configured to be “stateful” in the Galleyfile, Galley will not recreate it. This is
useful for database services that you’d like to avoid wiping in most cases. The `--recreate` and 
`--unprotectStateful` command line options affect these behaviors. See `galley run --help` for more info.



Run also takes a number of parameters that are the equivalent to `docker run` parameters. See `galley run --help`
for a complete list.

### Docker defaults

Galley uses a handful of defaults when working with Docker containers that we’ve found are appropriate for
development and testing. You should be aware of these, especially if you have a lot of other Docker experience.
If these aren’t working out for you, let us know; we always want to learn about new use cases!

(In these cases, the “primary service” is the one specified on the command line.)

 - If Galley is being run in a TTY, the primary service’s container is, too (`docker run -t`)
 - The primary service container is always run with STDIN allocated (`docker run -i`)
 - The primary service container is always removed when Galley stops (`docker run --rm`)
 - Volumes are always removed when removing a container (`docker rm -v`)






Galley is a tool for managing docker dependencies.
Docker makes it easy to connect two containers together, through '--links', but managing
what services your infrastructure uses, and how those services are connected together can
be challenging with Docker alone. Galley bridges that gap, by letting you start exactly the
containers you need to develop and test your services.

Galley lets you think about your code in terms of 'services' rather than just containers.
A service is simply a single container that depends on a fixed set of other containers, and the set of
dependencies may vary between environments (dev, test, integration, etc).

When you start, create, or run a service, for a particular environment galley knows to make sure that
its linked dependencies are running too.

Using galley is a two step process:

1. Write a Galleyfile defining your applications, dependencies, and environments, and point galley at the file.
  - Galleyfiles are executable JS (or coffeescript), so you can treat your Galleyfile like code: DRY, version controlled, and composable.

1. Run `galley run your-application.environment`
  - Galley respects familiar docker syntax
  - Supports volume mapping, exposing ports, attaching and detaching running containers, and setting environment variables
  - Can map local change into the container FAST, using a special rsync container. Invaluable for doing development with docker on a Mac without paying the NFS performance cost.

Use `galley pull your-application.environment` to bring all the images your application depends on to their latest version.

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


