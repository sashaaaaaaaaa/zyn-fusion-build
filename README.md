# Zyn-Fusion Slackware Build

Slackware build scripts for Zyn-Fusion. Everything gets deployed under
`/opt/zyn-fusion/` — no FHS symlink hacks, no filesystem pollution.

These build scripts (and only these build scripts) are licensed under the
WTFPL.

---

## Quick start

```shell
git clone -b slackware-opt git@github.com:sashaaaaaaaaa/zyn-fusion-build.git
cd zyn-fusion-build
sudo make -f Makefile.linux.mk install_deps
make -f Makefile.linux.mk slackware-pkg
sudo installpkg build/zyn-fusion-*_1.tgz
zyn-fusion
```

## Patches

The `slackware-opt` branch patches the upstream source to load assets
from `/opt/zyn-fusion/` instead of FHS paths or relative paths that
break at runtime.

Patches live in `patches/*.patch` and are applied automatically during
`build_zest` (after `git checkout` and before `make`, then reverted
after `pack`). To add a new patch:

1. Make changes in `src/mruby-zest-build/`
2. `cd src/mruby-zest-build && git diff path/to/file > ../patches/NN-description.patch`
3. Commit the patch to the main repo

## Build targets

| Target | Description |
|--------|-------------|
| `slackware-pkg` | Full build + Slackware package (`build/*.tgz`) |
| `build_zest` | Build only the Zest UI (skips ZynAddSubFX) |
| `zynaddsubfx` | Build only the ZynAddSubFX engine |

Set `MODE=release` to build the non-demo version:

```shell
make MODE=release -f Makefile.linux.mk slackware-pkg
```
