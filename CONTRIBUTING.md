# Contributing

We love pull requests from everyone. By participating in this project, you
agree to abide by the Twitter Open Source [code of conduct].

[code of conduct]: https://engineering.twitter.com/opensource/code-of-conduct

Fork, then clone the repo:

    git clone git@github.com:your-username/galley.git

Make sure your machine is set up for galley, the getting started guide in the [README]

Test your local galley changes

    npm watch # compiles and watches your local galley
    npm link # from the galley repo, symlinks your local version of galley to be globally installed
    cd ../directory-with-galleyfile
    npm link galley # symlinks from your local node modules to your global galley
    # Check that your local galley is running

Make sure the tests pass:

    gulp test
    gulp acceptance

Make your change. Add tests for your change. Make the tests pass:

    gulp test
    gulp acceptance

Push to your fork and [submit a pull request][pr].

[pr]: https://github.com/crashlytics/galley/compare

At this point you're waiting on us. We like to at least comment on pull requests
within three business days (and, typically, one business day). We may suggest
some changes or improvements or alternatives.

Some things that will increase the chance that your pull request is accepted:

* Write tests.
* Follow our [style guide][style].
* Write a [good commit message][commit].

[style]: https://github.com/polarmobile/coffeescript-style-guide
[commit]: http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html
