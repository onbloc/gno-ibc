// Copy P- labels from issues linked to a pull request.
//
// A- and T- labels are managed by other automation, so this script only
// propagates priority labels.
//
// Linked issues are those referenced through closing keywords such as
// "Closes #N" or "Fixes #N".
//
// Invoked from .github/workflows/labeler.yml.

const fs = require('fs');
const path = require('path');

const LABEL_PREFIXES = ['P-'];

const LINKED_ISSUES_QUERY = fs.readFileSync(
  path.join(__dirname, 'queries', 'linked-issues.graphql'),
  'utf8',
);

module.exports = async ({ github, context, core }) => {
  const { owner, repo } = context.repo;
  const prNumber = context.payload.pull_request.number;

  const result = await github.graphql(LINKED_ISSUES_QUERY, {
    owner,
    repo,
    pr: prNumber,
  });
  const issues = result.repository.pullRequest.closingIssuesReferences.nodes;

  const labels = new Set();
  for (const issue of issues) {
    for (const label of issue.labels.nodes) {
      if (LABEL_PREFIXES.some((prefix) => label.name.startsWith(prefix))) {
        labels.add(label.name);
      }
    }
  }

  if (labels.size === 0) {
    core.info('No P- labels found on linked issues.');
    return;
  }

  await github.rest.issues.addLabels({
    owner,
    repo,
    issue_number: prNumber,
    labels: [...labels],
  });
  core.info(`Copied labels from linked issues: ${[...labels].join(', ')}`);
};
