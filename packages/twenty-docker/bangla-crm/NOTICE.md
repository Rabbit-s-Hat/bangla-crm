# Notices

## Bangla CRM
Bangla CRM is a modified version of **Twenty** (<https://github.com/twentyhq/twenty>), copyright Twenty.com, PBC and contributors.
The changes add a Bangla (bn-BD) translation, make Bangla the default interface language, and add this installation package.

- **Licence:** GNU Affero General Public License, version 3 (AGPL-3.0), with Twenty's additional permission (the "Twenty Application Exception"). The full licence text is in the `LICENSE` file of this package and of the source repository.
- **Source code (AGPL section 13):** the complete corresponding source code of this version is at <https://github.com/Rabbit-s-Hat/bangla-crm>. Each release is tagged `bangla-vX.Y.Z`, and the Docker image of a release carries the same version number.
- **Commercially licensed parts:** some Twenty source files are marked `@license Enterprise` and are covered by the *Twenty.com Commercial License* (at the end of `LICENSE`), not by the AGPL. They are part of the Twenty code base that this image is built from. Features that Twenty sells (billing, SSO, row-level permissions and similar) are not enabled by this package. Twenty's software currently lets custom AI providers be used without an Enterprise key for up to 25 workspace members. Using Enterprise features beyond what Twenty offers without a subscription requires a Twenty Enterprise subscription.

## Trademarks
"Twenty" and the Twenty logo are trademarks of Twenty.com, PBC (see `TRADEMARK.md` in the source repository). Bangla CRM is an independent product **built on Twenty**. It is **not** affiliated with or endorsed by Twenty.com, PBC.

## Third-party components used by this package
| Component | Licence |
|---|---|
| PostgreSQL (`postgres` image) | PostgreSQL Licence |
| Redis (`redis` image, version 7) | BSD-3-Clause |
| Caddy (`caddy` image, cloud installs only) | Apache-2.0 |
| Docker / Docker Compose | Apache-2.0 (Docker Desktop has its own licence terms) |

Other open-source libraries included in the Bangla CRM image keep their own licences. See the source repository for details.
