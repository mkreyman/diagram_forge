# Configurable AI Prompts

## Overview

AI prompts are editable via the admin interface at `/admin/prompts`. Hardcoded defaults are used until an admin customizes a prompt. Database stores only customizations.

## Configurable Prompts

| Key | Description |
|-----|-------------|
| `concept_system` | System prompt for concept extraction |
| `diagram_system` | System prompt for diagram generation |
| `fix_mermaid_syntax` | Template for fixing syntax errors (uses `{{MERMAID_CODE}}` and `{{SUMMARY}}` placeholders) |

## Architecture

### Files Created

- `priv/repo/migrations/*_create_prompts.exs` - Database table
- `lib/diagram_forge/ai/prompt.ex` - Ecto schema
- `lib/diagram_forge/ai.ex` - Context with ETS caching
- `lib/diagram_forge_web/live/admin/prompt_live.ex` - List page
- `lib/diagram_forge_web/live/admin/prompt_edit_live.ex` - Edit page

### How It Works

1. **ETS Cache** - Started in `application.ex`, provides fast reads
2. **Lookup Flow** - Check cache → Check DB → Fall back to hardcoded default
3. **Cache Invalidation** - Automatic on create/update/delete

### Admin Features

- View all prompts with "Default" or "Customized" badges
- Edit any prompt (creates DB record on first save)
- Reset to Default (deletes DB record, reverts to hardcoded)
- Reset button disabled when already at default

## Database Schema

```
prompts
├── id: binary_id (PK)
├── key: string (unique, not null)
├── content: text (not null)
├── description: string
└── timestamps
```

## Test Coverage

54 tests covering:
- AI context (caching, CRUD, status helpers)
- Prompt schema (changesets, constraints)
- Admin LiveViews (access control, list, edit, reset)
- Placeholder replacement for `fix_mermaid_syntax`
