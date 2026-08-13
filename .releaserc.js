module.exports = {
  "branches": [
    "main",
    "master",
    { "name": "release/*", "prerelease": "rc" },
    { "name": "feature/*", "prerelease": true },
    { "name": "fix/*", "prerelease": true }
  ],
  "tagFormat": '${version}',
  "plugins": [
    [
      "@semantic-release/commit-analyzer",
      { "preset": "conventionalcommits" }
    ],
    [
      "@semantic-release/release-notes-generator",
      {
        "preset": "conventionalcommits",
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
