import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const main = readFileSync(join(root, "main.tf"), "utf8");
const variables = readFileSync(join(root, "variables.tf"), "utf8");
const readme = readFileSync(join(root, "README.md"), "utf8");

assert.match(variables, /variable "github_environment"/);
assert.match(variables, /type\s*=\s*string/);
assert.match(variables, /default\s*=\s*null/);
assert.match(main, /var\.github_environment == null/);
assert.match(main, /:environment:/);
assert.match(main, /replace\(var\.github_environment, ":", "%3A"\)/);
assert.match(readme, /repo:UseImpel@283797627\/impel-sessions@1304531882:environment:Production/);

const expectedSubjects = new Map([
  ["dev", "repo:UseImpel@283797627/impel-sessions@1304531882:ref:refs/heads/dev"],
  ["Production", "repo:UseImpel@283797627/impel-sessions@1304531882:environment:Production"],
  ["Production:SEA", "repo:UseImpel@283797627/impel-sessions@1304531882:environment:Production%3ASEA"],
]);
for (const [target, subject] of expectedSubjects) {
  const rendered = target === "dev"
    ? `repo:UseImpel@283797627/impel-sessions@1304531882:ref:refs/heads/${target}`
    : `repo:UseImpel@283797627/impel-sessions@1304531882:environment:${target.replaceAll(":", "%3A")}`;
  assert.equal(rendered, subject, `subject rendering for ${target}`);
}

process.stdout.write("github-deploy-role OIDC subject contract is valid.\n");
