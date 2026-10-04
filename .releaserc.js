// semantic-release — https://semantic-release.gitbook.io
// Runs in CI on every push to main (.github/workflows/release.yml) and
// publishes a GitHub Release + git tag. No CHANGELOG.md, no commit back.
//
// preset: `conventionalcommits`, matching commitlint. NOT `angular`: the
// angular parser doesn't understand the `type!:` header at all, so
// `feat!: ...` produced NO release (verified against
// @semantic-release/commit-analyzer) — only a `BREAKING CHANGE:` footer
// was ever detected as major.
//
// conventional-changelog-conventionalcommits is held at ^9 in package.json:
// 10.x requires conventional-changelog-writer@9, but
// @semantic-release/release-notes-generator (14.x, latest stable) still
// depends on writer ^8, and generateNotes fails with `Missing helper:
// "conventional-changelog-conventionalcommits requires
// conventional-changelog-writer@9 or newer"` (broke the 4.0.1 release).
// Move to ^10 only together with a release-notes-generator on writer@9.
//
// branches: main only. The release workflow only runs on main, so the old
// release/*, feature/*, fix/* prerelease entries never produced anything —
// and feature/* and fix/* shared the `beta` prerelease id, which
// semantic-release rejects (EPRERELEASEBRANCHES: prerelease ids must be
// unique per branch) as soon as two matching branches exist on the remote,
// failing the release on main too. `master` doesn't exist.
//
// tagFormat: unprefixed (`3.2.0`), deliberately. Releases from 2.0.0 on are
// tagged without a `v`; only the old 1.x tags have one. Switching to
// `v${version}` would make semantic-release ignore every tag since 2.0.0
// and compute the next version from v1.6.0.
module.exports = {
  branches: ['main'],
  tagFormat: '${version}',
  plugins: [
    ['@semantic-release/commit-analyzer', { preset: 'conventionalcommits' }],
    [
      '@semantic-release/release-notes-generator',
      {
        preset: 'conventionalcommits',
        writerOpts: {
          commitsSort: ['scope', 'subject'],
        },
      },
    ],
    '@semantic-release/github',
  ],
};
