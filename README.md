## Overview
Galley is a tool for managing docker dependencies.
Docker makes it easy to connect two containers together, through '--links', but managing
what services your infrastructure uses, and how those services are connected together can
be challenging with docker alone. Galley bridges that gap.

Galley lets you think about your code in terms of 'services' rather than just containers.
A service is simply a single container that depends on a fixed set of other containers.

When you start, create, or run a service, galley knows to make sure that its linked dependencies are
running too.

## Installation

```
$ npm install -g gulp-cli
$ git clone git@github.com:crashlytics/galley.git
$ npm install
$ gulp build
$ npm install -g
```

## Getting Started

See the [Crashlytics Dockerfiles](http://github.com/crashlytics/dockerfiles) repo for how to get
started with Docker and Galley.

## Tech Details
galley is written in coffeescript with node.js

built with gulp

tested with mocha

