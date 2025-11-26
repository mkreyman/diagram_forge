# DiagramForge Scripts

Utility scripts for diagram validation, export, and maintenance.

## Diagram Validation

Validates all Mermaid diagrams in the database for syntax errors.

### Quick Usage

```bash
# Export diagrams from database
mix run scripts/export_diagrams.exs

# Validate exported diagrams (run from project root)
cd assets && node ../scripts/validate_mermaid.mjs
```

### Files

- `export_diagrams.exs` - Elixir script to export diagrams to JSON
- `validate_mermaid.mjs` - Node.js script using mermaid-cli for validation

### Output

Results are written to `/tmp/diagram_validation_results.json` with structure:
```json
{
  "valid": [{ "id": "...", "title": "..." }],
  "invalid": [{ "id": "...", "title": "...", "error": "...", "source": "..." }]
}
```

### Requirements

The validation script requires mermaid-cli which is installed in the assets folder:
```bash
cd assets && npm install @mermaid-js/mermaid-cli
```

## Common Issues Found

Based on validation runs, common Mermaid syntax errors include:

1. **Nested quotes** - `["a"]` inside already-quoted labels
2. **Trailing periods** - Lines ending with `.` instead of `;`
3. **Unquoted special chars** - `&`, `(`, `)`, `{`, `}` need quoting
4. **Empty edge labels** - `-->|""|` empty strings
5. **Wrong arrow syntax** - `-->>` in flowcharts (sequence diagram syntax)

See `docs/broken_diagrams_analysis.md` for detailed analysis.
