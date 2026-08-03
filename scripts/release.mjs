#!/usr/bin/env node

/**
 * release.mjs
 *
 * Releases every plugin in packages/ that changed since its last git tag
 * (tag format: <plugin-name>@<version>). Claude Code plugins install from a
 * git marketplace, not npm, so this script does NOT publish to a registry —
 * it bumps the plugin's package.json (via commit-and-tag-version), syncs the
 * resulting version into the plugin's .claude-plugin/plugin.json and the
 * root .claude-plugin/marketplace.json, then tags and pushes.
 *
 * Usage:
 *   node scripts/release.mjs
 *   node scripts/release.mjs --dry-run        (simulate only)
 *   node scripts/release.mjs --force / -f      (release even without changes)
 */

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { standardVersionCommand } from './release-helpers.mjs';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const ROOT = join(__dirname, '..');
const PACKAGES_DIR = join(ROOT, 'packages');
const MARKETPLACE_PATH = join(ROOT, '.claude-plugin', 'marketplace.json');

const isDryRun = process.argv.includes('--dry-run') || process.argv.includes('-n');
const isForced = process.argv.includes('--force') || process.argv.includes('-f');

function exec(cmd, opts = {}) {
  return execSync(cmd, { cwd: ROOT, stdio: 'pipe', encoding: 'utf-8', ...opts });
}

function execIn(pkgDir, cmd, opts = {}) {
  return execSync(cmd, { cwd: pkgDir, stdio: 'inherit', encoding: 'utf-8', ...opts });
}

function tagExists(tag) {
  try {
    exec(`git rev-parse "${tag}"`, { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

function packageHasChangesSinceTag(tag, pkgDir) {
  try {
    exec(`git diff --quiet "${tag}" -- "${pkgDir}"`, { stdio: 'pipe' });
    return false; // no changes
  } catch {
    return true; // changes found
  }
}

function isWorkingTreeClean() {
  try {
    return exec(`git status --porcelain`, { stdio: 'pipe' }).trim().length === 0;
  } catch {
    return false;
  }
}

// After commit-and-tag-version bumps a plugin's package.json, fold that version
// into its plugin.json and the matching root marketplace.json entry.
function syncPluginVersion(pkgPath, name) {
  const pkgJson = JSON.parse(readFileSync(join(pkgPath, 'package.json'), 'utf-8'));
  const version = pkgJson.version;

  const pluginJsonPath = join(pkgPath, '.claude-plugin', 'plugin.json');
  const pluginJson = JSON.parse(readFileSync(pluginJsonPath, 'utf-8'));
  pluginJson.version = version;
  writeFileSync(pluginJsonPath, JSON.stringify(pluginJson, null, 2) + '\n');

  const marketplace = JSON.parse(readFileSync(MARKETPLACE_PATH, 'utf-8'));
  const entry = marketplace.plugins.find((p) => p.name === name);
  if (entry) entry.version = version;
  writeFileSync(MARKETPLACE_PATH, JSON.stringify(marketplace, null, 2) + '\n');

  return version;
}

console.log('═══════════════════════════════════════════');
console.log('  release — Claude Code plugins');
console.log(`  dry-run: ${isDryRun ? '✓' : '✗'}`);
console.log(`  force:   ${isForced ? '✓' : '✗'}`);
console.log('═══════════════════════════════════════════\n');

if (!isWorkingTreeClean()) {
  if (isDryRun) {
    console.log('⚠  Working tree dirty — dry-run continues anyway (no real changes).\n');
  } else {
    console.error('✗ Working tree not clean. Commit or stash before releasing.');
    process.exit(1);
  }
}

const packages = readdirSync(PACKAGES_DIR, { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => d.name);

let released = 0;
let skipped = 0;

for (const pkg of packages) {
  const pkgPath = join(PACKAGES_DIR, pkg);
  const pkgJsonPath = join(pkgPath, 'package.json');

  let pkgJson;
  try {
    pkgJson = JSON.parse(readFileSync(pkgJsonPath, 'utf-8'));
  } catch {
    console.log(`⚠  ${pkg}: invalid or missing package.json, skipped`);
    continue;
  }

  const name = pkgJson.name;
  const version = pkgJson.version;
  const tag = `${name}@${version}`;

  console.log(`\n── ${name} ────────────────────────────────`);
  console.log(`   current version: ${version}`);

  // A missing tag means this is the first release of this version.
  const isFirstRelease = !tagExists(tag);

  if (!isFirstRelease) {
    console.log(`   tag found: ${tag}`);

    if (!packageHasChangesSinceTag(tag, `packages/${pkg}`)) {
      if (isForced) {
        console.log(`   ⚑ no changes but --force given, proceeding anyway`);
      } else {
        console.log(`   ✓ no changes, skipped`);
        skipped++;
        continue;
      }
    }
    console.log(`   ↻ changes detected, releasing`);
  } else {
    console.log(`   ⚑ no tag found, initial release`);
  }

  if (isDryRun) {
    console.log(`   [dry-run] commit-and-tag-version --tag-prefix "${name}@"`);
    execIn(pkgPath, standardVersionCommand(ROOT, name, true, isFirstRelease), { stdio: 'inherit' });
    console.log(`   [dry-run] sync plugin.json + marketplace.json (skipped)`);
    console.log(`   [dry-run] git push --follow-tags (skipped)`);
  } else {
    try {
      // Bump package.json + CHANGELOG, commit, tag.
      execIn(pkgPath, standardVersionCommand(ROOT, name, false, isFirstRelease), { stdio: 'inherit' });

      // Fold the plugin manifest + marketplace listing into the same release commit.
      const newVersion = syncPluginVersion(pkgPath, name);
      const newTag = `${name}@${newVersion}`;

      console.log(`   → syncing plugin.json + marketplace.json to ${newVersion}...`);
      exec(`git add "packages/${pkg}/.claude-plugin/plugin.json" ".claude-plugin/marketplace.json"`);
      exec(`git commit --amend --no-edit`);
      exec(`git tag -f "${newTag}" HEAD`);

      console.log(`   → pushing tag...`);
      exec(`git push --follow-tags origin main`);

      released++;
      console.log(`   ✅ ${name} released as ${newTag}!`);
    } catch (err) {
      console.error(`   ❌ Error releasing ${name}:`, err.message);
      process.exit(1);
    }
  }
}

console.log('\n═══════════════════════════════════════════');
console.log(`  Summary:`);
console.log(`  • released: ${released}`);
console.log(`  • skipped:  ${skipped}`);
console.log(`  • total:    ${packages.length}`);
console.log('═══════════════════════════════════════════\n');
