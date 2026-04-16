#!/usr/bin/env node

import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  chmodSync,
  appendFileSync,
} from "node:fs";
import { join, dirname, isAbsolute, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const TEMPLATES_DIR = join(__dirname, "..", "templates");

const GITIGNORE_ENTRY = ".claude/worktrees";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function log(msg) {
  console.log(msg);
}

function fatal(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

function printUsage() {
  log(
    `
Usage: worktree-tools [options]

Install worktree lifecycle files into the root of the current git repository
(the directory that contains .git). Run from anywhere inside the repo — the
installer always resolves and writes to the repo root.

Options:
  --force, -f            Overwrite existing files
  --dry-run, -n          Print what would happen without writing
  --skills-only          Install only the /wt-* skills under .claude/skills/.
                         Skips wt-setup.sh and the .gitignore entry. Useful for
                         updating skills without touching an already-customized
                         setup script.
  --scripts-dir <path>   Relative path (from repo root) for wt-setup.sh
                         (default: scripts). Must stay inside the repo.
  --help, -h             Show this help message
`.trim(),
  );
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = argv.slice(2);
  const flags = {
    force: false,
    dryRun: false,
    skillsOnly: false,
    scriptsDir: "scripts",
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--force":
      case "-f":
        flags.force = true;
        break;
      case "--dry-run":
      case "-n":
        flags.dryRun = true;
        break;
      case "--skills-only":
        flags.skillsOnly = true;
        break;
      case "--scripts-dir":
        i++;
        if (!args[i] || args[i].startsWith("-")) {
          fatal("--scripts-dir requires a path argument");
        }
        flags.scriptsDir = validateScriptsDir(args[i]);
        break;
      case "--help":
      case "-h":
        printUsage();
        process.exit(0);
        break;
      default:
        if (args[i].startsWith("-")) {
          fatal(`Unknown flag: ${args[i]}\nRun with --help for usage.`);
        }
        fatal(`Unexpected argument: ${args[i]}\nRun with --help for usage.`);
    }
  }

  return flags;
}

// ---------------------------------------------------------------------------
// Git repo verification and root resolution
// ---------------------------------------------------------------------------

function assertGitRepo(cwd) {
  try {
    execSync("git rev-parse --is-inside-work-tree", {
      cwd,
      stdio: "pipe",
    });
  } catch {
    fatal(
      "Not a git repository.\n" +
        "Run this command from inside a git repo, or initialize one with `git init`.",
    );
  }
}

/**
 * Resolve the repository root (the directory that contains .git / .claude).
 * Always use this as the write target instead of process.cwd() so that the
 * installer works correctly when invoked from a subdirectory.
 */
function getRepoRoot(cwd) {
  try {
    return execSync("git rev-parse --show-toplevel", { cwd, stdio: "pipe" })
      .toString()
      .trim();
  } catch {
    fatal("Could not determine git repository root.");
  }
}

/**
 * Validate that --scripts-dir is a relative path that stays inside the repo.
 * Absolute paths and paths containing `..` components that escape the root are
 * rejected because they could silently write outside the target repository.
 */
function validateScriptsDir(value) {
  const normalized = normalize(value);
  if (isAbsolute(normalized)) {
    fatal(
      `--scripts-dir must be a relative path inside the repository, got: ${value}`,
    );
  }
  if (normalized.startsWith("..")) {
    fatal(
      `--scripts-dir must not escape the repository root (path starts with '..'): ${value}`,
    );
  }
  return normalized;
}

// ---------------------------------------------------------------------------
// File manifest
// ---------------------------------------------------------------------------

function getManifest(scriptsDir) {
  return [
    {
      src: "wt-setup.sh",
      dest: `${scriptsDir}/wt-setup.sh`,
      executable: true,
    },
    {
      src: "skills/wt-open/SKILL.md",
      dest: ".claude/skills/wt-open/SKILL.md",
      executable: false,
    },
    {
      src: "skills/wt-merge/SKILL.md",
      dest: ".claude/skills/wt-merge/SKILL.md",
      executable: false,
    },
    {
      src: "skills/wt-close/SKILL.md",
      dest: ".claude/skills/wt-close/SKILL.md",
      executable: false,
    },
    {
      src: "skills/wt-list/SKILL.md",
      dest: ".claude/skills/wt-list/SKILL.md",
      executable: false,
    },
    {
      src: "skills/wt-adopt/SKILL.md",
      dest: ".claude/skills/wt-adopt/SKILL.md",
      executable: false,
    },
    {
      src: "skills/wt-help/SKILL.md",
      dest: ".claude/skills/wt-help/SKILL.md",
      executable: false,
    },
    {
      src: "skills/wt-cleanup/SKILL.md",
      dest: ".claude/skills/wt-cleanup/SKILL.md",
      executable: false,
    },
  ];
}

// ---------------------------------------------------------------------------
// File installation
// ---------------------------------------------------------------------------

function installFiles({ manifest, templatesDir, targetDir, force, dryRun }) {
  const results = { written: [], skipped: [], overwritten: [] };

  for (const entry of manifest) {
    const srcPath = join(templatesDir, entry.src);
    const destPath = join(targetDir, entry.dest);
    const destDir = dirname(destPath);
    const relDest = entry.dest;

    let content;
    try {
      content = readFileSync(srcPath, "utf8");
    } catch (err) {
      fatal(`Template not found: ${entry.src}\n${err.message}`);
    }

    const exists = existsSync(destPath);

    if (exists && !force) {
      results.skipped.push(relDest);
      log(`  skip      ${relDest} (already exists, use --force to overwrite)`);
      continue;
    }

    if (dryRun) {
      const verb = exists ? "overwrite" : "write";
      log(`  ${verb.padEnd(10)}${relDest} (dry run)`);
      (exists ? results.overwritten : results.written).push(relDest);
      continue;
    }

    try {
      mkdirSync(destDir, { recursive: true });
      writeFileSync(destPath, content, "utf8");
      if (entry.executable) {
        chmodSync(destPath, 0o755);
      }
    } catch (err) {
      fatal(`Failed to write ${relDest}: ${err.message}`);
    }

    if (exists) {
      results.overwritten.push(relDest);
      log(`  overwrite ${relDest}`);
    } else {
      results.written.push(relDest);
      log(`  write     ${relDest}`);
    }
  }

  return results;
}

// ---------------------------------------------------------------------------
// .gitignore management
// ---------------------------------------------------------------------------

function ensureGitignoreEntry(targetDir, entry, dryRun) {
  const gitignorePath = join(targetDir, ".gitignore");

  if (existsSync(gitignorePath)) {
    const content = readFileSync(gitignorePath, "utf8");
    const lines = content.split("\n");
    if (lines.some((line) => line.trim() === entry)) {
      log(`  skip      .gitignore (already contains '${entry}')`);
      return false;
    }
    if (dryRun) {
      log(`  append    '${entry}' to .gitignore (dry run)`);
      return true;
    }
    const prefix = content.endsWith("\n") ? "" : "\n";
    appendFileSync(gitignorePath, `${prefix}${entry}\n`, "utf8");
    log(`  append    '${entry}' to .gitignore`);
    return true;
  }

  if (dryRun) {
    log(`  create    .gitignore with '${entry}' (dry run)`);
    return true;
  }
  writeFileSync(gitignorePath, `${entry}\n`, "utf8");
  log(`  create    .gitignore with '${entry}'`);
  return true;
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

function printSummary(results, dryRun, skillsOnly) {
  log("");
  if (dryRun) {
    log("Dry run complete. No files were written.");
  } else {
    const total = results.written.length + results.overwritten.length;
    if (total === 0) {
      log("Nothing to do. All files already exist (use --force to overwrite).");
    } else {
      log(`Done. ${total} file(s) installed.`);
    }
  }

  if (results.skipped.length > 0) {
    log(`${results.skipped.length} file(s) skipped (already exist).`);
  }

  if (
    !dryRun &&
    (results.written.length > 0 || results.overwritten.length > 0)
  ) {
    log("");
    log("Next steps:");
    log("  1. Review the installed files");
    log("  2. Commit them to your repo");
    if (!skillsOnly) {
      log(
        "  3. Open Claude Code and run /wt-adopt to customize the setup script for this repo",
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const flags = parseArgs(process.argv);
  const cwd = process.cwd();

  assertGitRepo(cwd);

  // Always install into the repo root (the directory containing .git/.claude),
  // regardless of which subdirectory the user invoked the command from.
  const repoRoot = getRepoRoot(cwd);

  if (!existsSync(TEMPLATES_DIR)) {
    fatal(
      `Templates directory not found at ${TEMPLATES_DIR}.\n` +
        "This is a bug in @thinkvelta/claude-worktree-tools. Please report it.",
    );
  }

  let manifest = getManifest(flags.scriptsDir);
  if (flags.skillsOnly) {
    manifest = manifest.filter((entry) =>
      entry.src.startsWith("skills/"),
    );
  }

  log(
    flags.skillsOnly
      ? "Installing worktree skills only..."
      : "Installing worktree tools...",
  );
  log(`Target: ${repoRoot}`);
  log("");

  const results = installFiles({
    manifest,
    templatesDir: TEMPLATES_DIR,
    targetDir: repoRoot,
    force: flags.force,
    dryRun: flags.dryRun,
  });

  if (!flags.skillsOnly) {
    ensureGitignoreEntry(repoRoot, GITIGNORE_ENTRY, flags.dryRun);
  }

  printSummary(results, flags.dryRun, flags.skillsOnly);
}

main();
