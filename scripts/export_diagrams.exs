# Export diagrams for validation
# Run with: mix run scripts/export_diagrams.exs
#
# This exports all diagrams to /tmp/diagrams_to_validate.json
# which can then be validated with: node scripts/validate_mermaid.mjs

alias DiagramForge.Repo
alias DiagramForge.Diagrams.Diagram
import Ecto.Query

output_file = System.get_env("OUTPUT_FILE") || "/tmp/diagrams_to_validate.json"

diagrams = Repo.all(
  from d in Diagram,
  select: %{
    id: d.id,
    title: d.title,
    source: d.diagram_source
  }
)

json = Jason.encode!(diagrams, pretty: true)
File.write!(output_file, json)

IO.puts("Exported #{length(diagrams)} diagrams to #{output_file}")
