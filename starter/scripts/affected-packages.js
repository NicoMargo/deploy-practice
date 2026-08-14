#!/usr/bin/env node
//
// Works out which packages and services are affected by a list of changed files.
//
//   node affected-packages.js <file> [file...]
//
// The graph comes from the repo itself, so adding a service or changing a
// dependency needs no change here.

const fs = require("fs");
const path = require("path");

// This script lives in starter/scripts, so the monorepo root is one level up.
const ROOT = path.resolve(__dirname, "..");
const GROUPS = ["packages", "services"];

// Read every workspace: its npm name, its folder, and which internal packages
// it depends on.
function readWorkspaces() {
  const workspaces = [];

  for (const group of GROUPS) {
    const groupPath = path.join(ROOT, group);
    if (!fs.existsSync(groupPath)) continue;

    for (const folder of fs.readdirSync(groupPath)) {
      const manifest = path.join(groupPath, folder, "package.json");
      if (!fs.existsSync(manifest)) continue;

      const pkg = JSON.parse(fs.readFileSync(manifest, "utf8"));

      workspaces.push({
        name: pkg.name,             // "@aceup/orders-service"
        dir: `${group}/${folder}`,  // "services/orders"
        isService: group === "services",
        // Only our own packages matter. express and the rest do not.
        deps: Object.keys(pkg.dependencies ?? {}).filter((d) => d.startsWith("@aceup/")),
      });
    }
  }

  return workspaces;
}

// Which workspace does this file belong to? The one with the longest matching
// folder, so "services/orders" wins over a shorter path.
function ownerOf(file, workspaces) {
  return workspaces
    .filter((w) => file === w.dir || file.startsWith(`${w.dir}/`))
    .sort((a, b) => b.dir.length - a.dir.length)[0];
}

// Add everything that depends on these packages, directly or through another
// package. Keep going until nothing new shows up.
function withDependents(names, workspaces) {
  const affected = new Set(names);
  const queue = [...names];

  while (queue.length > 0) {
    const current = queue.pop();

    for (const w of workspaces) {
      if (w.deps.includes(current) && !affected.has(w.name)) {
        affected.add(w.name);
        queue.push(w.name);
      }
    }
  }

  return affected;
}

function main() {
  const changedFiles = process.argv.slice(2).filter(Boolean);

  if (changedFiles.length === 0) {
    console.error("usage: node affected-packages.js <file> [file...]");
    process.exit(1);
  }

  const workspaces = readWorkspaces();
  const changed = new Set();
  let rootChange = false;

  for (const file of changedFiles) {
    // git runs at the repo root, one level above starter/.
    if (!file.startsWith("starter/")) {
      // Environment manifests only say which image to deploy, they never change
      // what is inside one, so they must not trigger a rebuild. Without this the
      // manifest pull request rebuilds everything, gets new digests, and opens
      // another manifest pull request.
      if (file.startsWith("infra/envs/")) continue;

      // CI config, modules, docs. We cannot tell what they affect, so rebuild all.
      rootChange = true;
      continue;
    }

    const owner = ownerOf(file.slice("starter/".length), workspaces);

    if (owner) {
      changed.add(owner.name);
    } else {
      // Lockfile, root package.json, scripts: same reasoning as above.
      rootChange = true;
    }
  }

  const affected = rootChange
    ? new Set(workspaces.map((w) => w.name))
    : withDependents([...changed], workspaces);

  const services = workspaces
    .filter((w) => w.isService && affected.has(w.name))
    .map((w) => w.dir);

  console.log(JSON.stringify({
    rootChange,
    affectedPackages: [...affected],
    affectedServices: services,
  }, null, 2));
}

main();
