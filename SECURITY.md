# Security Policy

Figures opens spreadsheet files from anywhere, so problems in how it reads them matter.

## Reporting a vulnerability

Please report security problems privately through GitHub's
[private vulnerability reporting](https://github.com/tariknaeem/Figures/security/advisories/new)
rather than in a public issue. Include the file or steps that trigger the problem and what you expected.

You should get a reply within a week. Please give a reasonable time for a fix before sharing details publicly.

## Scope

In scope: crashes, hangs, excessive memory use or code paths reachable from opening a crafted `.xlsx`, `.xlsm`
or `.csv` file, and anything that lets a file read or write outside what the user opened.

Figures does not run macros, follow external workbook links or make network requests.
