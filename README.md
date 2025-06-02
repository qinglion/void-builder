# Void Builder

This is a fork of VSCodium, which has a nice build pipeline that we're using for Void. Big thanks to the CodeStory team for inspiring this.

The purpose of this repo is to run [Github Actions](https://github.com/qinglion/void-builder/actions). These actions build all the Void assets (.dmg, .zip, etc), store them on a release in [`qinglion/binaries`](https://github.com/qinglion/binaries/releases), and then set the latest version in [`qinglion/versions`](https://github.com/qinglion/versions) so the versions can be tracked for updating in the Void app.

## Notes

- See `stable-macos.sh` for one of the main Actions with some comments added by the Void team.

- VSCodium comes with `.patch` files, including relevant ones to auto-updating, which are being applied when we build Void.

- For a list of all the places Void edited in this repo, search "Void" and "voideditor".

- We deleted some unused workflows (insider-* and stable-spearhead).
