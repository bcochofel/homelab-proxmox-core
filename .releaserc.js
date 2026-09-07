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
    "@semantic-release/github"
  ]
}
