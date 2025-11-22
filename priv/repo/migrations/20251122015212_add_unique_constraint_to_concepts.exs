defmodule DiagramForge.Repo.Migrations.AddUniqueConstraintToConcepts do
  use Ecto.Migration

  def up do
    # First, deduplicate existing concepts before adding the constraint
    # Strategy: For each (document_id, name) pair, keep the concept with:
    # 1. Most diagrams, or if tied
    # 2. Most recently created

    execute """
    WITH duplicates AS (
      SELECT
        document_id,
        name,
        array_agg(id ORDER BY
          (SELECT COUNT(*) FROM diagrams WHERE diagrams.concept_id = concepts.id) DESC,
          inserted_at DESC
        ) as concept_ids
      FROM concepts
      GROUP BY document_id, name
      HAVING COUNT(*) > 1
    ),
    concepts_to_keep AS (
      SELECT
        document_id,
        name,
        concept_ids[1] as keep_id,
        concept_ids[2:array_length(concept_ids, 1)] as delete_ids
      FROM duplicates
    ),
    -- Update diagrams to point to the concept we're keeping
    updated_diagrams AS (
      UPDATE diagrams
      SET concept_id = (
        SELECT keep_id
        FROM concepts_to_keep
        WHERE diagrams.concept_id = ANY(delete_ids)
        LIMIT 1
      )
      WHERE concept_id IN (
        SELECT unnest(delete_ids)
        FROM concepts_to_keep
      )
      RETURNING id
    )
    -- Delete duplicate concepts
    DELETE FROM concepts
    WHERE id IN (
      SELECT unnest(delete_ids)
      FROM concepts_to_keep
    );
    """

    # Now add the unique constraint
    drop_if_exists index(:concepts, [:document_id, :name])
    create unique_index(:concepts, [:document_id, :name])
  end

  def down do
    # Revert to non-unique index
    drop_if_exists index(:concepts, [:document_id, :name])
    create index(:concepts, [:document_id, :name])
  end
end
