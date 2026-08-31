# Connector tarball drop zone

CI downloads `printupkeep-connector-<version>.tgz` and its `.tgz.sha256` from
this repo's `connector-v<version>` GitHub release into this directory **before**
running the CustomPiOS build (see `.github/workflows/build.yml`). The chroot
script then installs from the local file, so nothing inside the chroot needs
network access or GitHub credentials.

For a local build, do the same by hand:

```sh
gh release download connector-v0.1.0 --repo online-concept-aps/printupkeep-os \
  --pattern 'printupkeep-connector-*' --dir src/modules/printupkeep/filesystem/connector/
```

The tarballs are gitignored — never commit them.
