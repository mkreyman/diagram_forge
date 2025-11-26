#!/usr/bin/env node
/**
 * Validate Mermaid diagrams using mermaid-cli
 *
 * Usage:
 *   1. First export diagrams: mix run scripts/export_diagrams.exs
 *   2. Then validate: node scripts/validate_mermaid.mjs
 *
 * Or use the combined script: ./scripts/validate_all_diagrams.sh
 */

import { run } from '@mermaid-js/mermaid-cli';
import { readFileSync, writeFileSync, mkdtempSync, rmSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, '..');

// Input/output files
const inputFile = process.argv[2] || '/tmp/diagrams_to_validate.json';
const outputFile = process.argv[3] || '/tmp/diagram_validation_results.json';

if (!existsSync(inputFile)) {
  console.error(`Error: Input file not found: ${inputFile}`);
  console.error('Run: mix run scripts/export_diagrams.exs first');
  process.exit(1);
}

// Read diagrams
const diagrams = JSON.parse(readFileSync(inputFile, 'utf8'));

console.log(`Validating ${diagrams.length} diagrams...\n`);

const results = {
  valid: [],
  invalid: []
};

// Create temp directory
const tempDir = mkdtempSync(join(tmpdir(), 'mermaid-validate-'));

let count = 0;
for (const diagram of diagrams) {
  count++;
  if (count % 50 === 0 || count === diagrams.length) {
    process.stdout.write(`${count}/${diagrams.length}\n`);
  } else {
    process.stdout.write('.');
  }

  if (!diagram.source) {
    results.invalid.push({
      id: diagram.id,
      title: diagram.title,
      error: 'No source code',
      source: null
    });
    continue;
  }

  const mmdFile = join(tempDir, 'input.mmd');
  const svgFile = join(tempDir, 'output.svg');

  writeFileSync(mmdFile, diagram.source);

  try {
    await run(mmdFile, svgFile, {
      parseMMDOptions: { suppressErrors: false },
      puppeteerConfig: { headless: 'new' },
      quiet: true
    });
    results.valid.push({
      id: diagram.id,
      title: diagram.title
    });
  } catch (err) {
    results.invalid.push({
      id: diagram.id,
      title: diagram.title,
      error: err.message || String(err),
      source: diagram.source
    });
  }
}

// Cleanup
try {
  rmSync(tempDir, { recursive: true, force: true });
} catch (e) {}

console.log(`\n\n=== RESULTS ===`);
console.log(`Valid: ${results.valid.length}`);
console.log(`Invalid: ${results.invalid.length}`);
console.log(`Success rate: ${((results.valid.length / diagrams.length) * 100).toFixed(1)}%\n`);

if (results.invalid.length > 0) {
  console.log(`=== INVALID DIAGRAMS ===\n`);

  // Group errors by type (first line)
  const errorTypes = {};
  for (const item of results.invalid) {
    const errorLines = item.error.split('\n');
    let errorKey = 'Unknown error';
    for (const line of errorLines) {
      if (line.includes('Parse error') || line.includes('Error:')) {
        errorKey = line.trim().substring(0, 80);
        break;
      }
    }
    if (!errorTypes[errorKey]) {
      errorTypes[errorKey] = [];
    }
    errorTypes[errorKey].push(item);
  }

  console.log(`Error types found: ${Object.keys(errorTypes).length}\n`);

  for (const [errorType, items] of Object.entries(errorTypes)) {
    console.log(`\n--- ${errorType} (${items.length} diagrams) ---`);
    const example = items[0];
    console.log(`Example: ${example.title}`);
    console.log(`ID: ${example.id}`);
    console.log(`Full error:\n${example.error}`);
    console.log(`Source:\n${example.source?.substring(0, 400)}...\n`);
  }
}

// Write detailed results to file
writeFileSync(outputFile, JSON.stringify(results, null, 2));
console.log(`\nDetailed results written to ${outputFile}`);
