class CreateMediaInputs < ActiveRecord::Migration[8.1]
  def change
    create_table :media_inputs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :source
      t.string :path
      t.string :kind
      t.text :description
      t.integer :width
      t.integer :height

      t.timestamps
    end
  end
end
