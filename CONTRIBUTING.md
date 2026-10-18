# Contributing

Thanks for your interest in Figures. Issues and pull requests are welcome.

## Before you open a pull request

- Build with `./scripts/build-mac-app.sh` and run `swift run SheetCoreChecks`; all checks must pass.
- Keep changes focused, and add checks to `Sources/SheetCoreChecks/main.swift` for engine changes.
- Do not include code, files or assets copied from Microsoft Excel or other proprietary software, or from
  projects whose license is not compatible with the MIT License.
- Report security problems privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

## License of contributions

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE), the same
license as the project, and that the project may continue to distribute it under that license.

## Developer Certificate of Origin

Every commit must be signed off to certify that you wrote it or otherwise have the right to submit it under the
project's license. Sign off by adding this line to your commit message, using your real name:

```
Signed-off-by: Your Name <your.email@example.com>
```

`git commit -s` adds it for you. Signing off means you agree to the Developer Certificate of Origin 1.1:

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```
