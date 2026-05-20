// Copy area (A-), priority (P-), and type (T-) labels from issues linked
// to a pull request onto the pull request itself.
//
// "Linked" means GitHub linked the issue through a closing keyword such as
// "Closes #N" or "Fixes #N". A plain "#N" reference does not count.
//
// Invoked from .github/workflows/labeler.yml via actions/github-script.

const fs = require('fs');
const path = require('path');

const LABEL_PREFIXES = ['A-', 'P-', 'T-'];

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
    core.info('No A-/P-/T- labels found on linked issues.');
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
