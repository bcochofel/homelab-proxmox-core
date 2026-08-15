module.exports = {
  "branches": [
    "main",
    "master",
    { "name": "release/*", "prerelease": "rc" },
    { "name": "feature/*", "prerelease": "beta" },
    { "name": "fix/*", "prerelease": "beta" }
  ],
  "tagFormat": '${version}',
  "plugins": [
    [
      "@semantic-release/commit-analyzer",
      { "preset": "angular" }
    ],
    [
      "@semantic-release/release-notes-generator",
      {
        "preset": "angular",
        "writerOpts": {
          "commitsSort": ["scope", "subject"]
        }
      }
    ],
    [
      "@semantic-release/changelog",
      {
        "changelogFile": "CHANGELOG.md",
        "changelogTitle": "# 📦 Changelog\n\nAll notable changes to this infrastructure project will be documented here."
      }
    ],
    "@semantic-release/github",
    [
      "@semantic-release/git",
      {
        "assets": ["CHANGELOG.md"],
        "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
      }
    ]
  ]
}
