// Validate sanitized Mermaid diagrams using mmdc (mermaid-cli)
// Run with: node validate_sanitized.mjs

import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'fs';
import { execSync } from 'child_process';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Read sanitized diagrams
const diagrams = JSON.parse(readFileSync('/tmp/diagrams_sanitized.json', 'utf8'));

console.log(`Validating ${diagrams.length} SANITIZED diagrams...\n`);

// Create temp directory for diagrams
const tempDir = '/tmp/mermaid_validation_sanitized';
try {
  rmSync(tempDir, { recursive: true, force: true });
} catch (e) {}
mkdirSync(tempDir, { recursive: true });

const results = {
  valid: [],
  invalid: []
};

const mmdc = join(__dirname, 'node_modules/.bin/mmdc');

for (let i = 0; i < diagrams.length; i++) {
  const diagram = diagrams[i];

  if (!diagram.source) {
    results.invalid.push({
      id: diagram.id,
      title: diagram.title,
      error: 'No source code',
      source: null
    });
    continue;
  }

  // Write diagram to temp file
  const inputFile = join(tempDir, `diagram_${i}.mmd`);
  const outputFile = join(tempDir, `diagram_${i}.svg`);

  writeFileSync(inputFile, diagram.source);

  try {
    // Try to render the diagram
    execSync(`${mmdc} -i "${inputFile}" -o "${outputFile}" 2>&1`, {
      timeout: 10000,
      encoding: 'utf8'
    });

    results.valid.push({
      id: diagram.id,
      title: diagram.title
    });

    process.stdout.write('.');
  } catch (err) {
    const errorOutput = err.stdout || err.stderr || err.message || String(err);

    results.invalid.push({
      id: diagram.id,
      title: diagram.title,
      error: errorOutput,
      source: diagram.source
    });

    process.stdout.write('x');
  }

  // Progress indicator
  if ((i + 1) % 50 === 0) {
    console.log(` ${i + 1}/${diagrams.length}`);
  }
}

console.log(`\n\n=== RESULTS AFTER SANITIZATION ===`);
console.log(`Valid: ${results.valid.length}`);
console.log(`Invalid: ${results.invalid.length}`);

const improvementRate = ((results.valid.length - 129) / 16 * 100).toFixed(1);
console.log(`\nImprovement: Fixed ${results.valid.length - 129} of 16 previously invalid diagrams (${improvementRate}%)`);

if (results.invalid.length > 0) {
  console.log(`\n=== REMAINING INVALID DIAGRAMS ===\n`);

  for (const item of results.invalid) {
    // Extract error message
    const lines = item.error.split('\n').filter(l => l.trim());
    let errorMsg = 'Unknown error';
    for (const line of lines) {
      if (line.includes('Error') || line.includes('error')) {
        errorMsg = line.trim().substring(0, 80);
        break;
      }
    }

    console.log(`- ${item.title}`);
    console.log(`  ID: ${item.id}`);
    console.log(`  Error: ${errorMsg}\n`);
  }
}

// Write detailed results to file
writeFileSync('/tmp/diagram_validation_sanitized_results.json', JSON.stringify(results, null, 2));
console.log(`\nDetailed results written to /tmp/diagram_validation_sanitized_results.json`);

// Cleanup
try {
  rmSync(tempDir, { recursive: true, force: true });
} catch (e) {}
