defmodule DiagramForge.Repo.Migrations.MakeConceptsGloballyUnique do
  use Ecto.Migration

  def up do
    # Step 1: Deduplicate concepts globally by name
    # Strategy: Keep the concept with most diagrams, or if tied, the oldest one
    execute """
    WITH duplicates AS (
      SELECT
        name,
        array_agg(id ORDER BY
          (SELECT COUNT(*) FROM diagrams WHERE diagrams.concept_id = concepts.id) DESC,
          inserted_at ASC
        ) as concept_ids
      FROM concepts
      GROUP BY name
      HAVING COUNT(*) > 1
    ),
    concepts_to_keep AS (
      SELECT
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

    # Step 2: Make document_id nullable (it now means "first seen in this document")
    alter table(:concepts) do
      modify :document_id, references(:documents, type: :binary_id),
        null: true,
        from: {references(:documents, type: :binary_id), null: false}
    end

    # Step 3: Drop the old unique index and create a new one on name only
    drop_if_exists index(:concepts, [:document_id, :name])
    create unique_index(:concepts, [:name])
  end

  def down do
    # Revert: Remove global unique constraint, add back per-document constraint
    drop_if_exists index(:concepts, [:name])
    create unique_index(:concepts, [:document_id, :name])

    # Make document_id required again (may fail if there are null values)
    alter table(:concepts) do
      modify :document_id, references(:documents, type: :binary_id),
        null: false,
        from: {references(:documents, type: :binary_id), null: true}
    end
  end
end
