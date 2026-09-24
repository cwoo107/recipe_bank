class AddInstructionPositionToStepsAndComponents < ActiveRecord::Migration[8.1]
  def up
    # Steps and component recipes share one ordered instruction list, so they
    # need a position in the same sequence. Step#position stays as it was —
    # acts_as_list still manages it — this is the merged ordering.
    add_column :steps,             :instruction_position, :integer
    add_column :recipe_components, :instruction_position, :integer

    # Existing recipes keep how they read today: own steps first, then the
    # components that were listed underneath them.
    execute <<~SQL
      UPDATE steps
         SET instruction_position = position
       WHERE position IS NOT NULL
    SQL

    execute <<~SQL
      UPDATE recipe_components
         SET instruction_position = COALESCE(position, 0) + COALESCE(
               (SELECT MAX(steps.position) FROM steps
                 WHERE steps.recipe_id = recipe_components.parent_recipe_id), 0)
    SQL

    add_index :steps,             [:recipe_id, :instruction_position]
    add_index :recipe_components, [:parent_recipe_id, :instruction_position],
              name: "index_recipe_components_on_parent_and_instruction_position"
  end

  def down
    remove_column :steps, :instruction_position
    remove_column :recipe_components, :instruction_position
  end
end
