fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios setup_signing

```sh
[bundle exec] fastlane ios setup_signing
```

Create App Store signing certs and profiles

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight

### ios nuke_signing

```sh
[bundle exec] fastlane ios nuke_signing
```

Delete old distribution signing from match

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
