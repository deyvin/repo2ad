class CreateCreatives < ActiveRecord::Migration[8.1]
  def change
    create_table :creatives do |t|
      t.references :project, null: false, foreign_key: true
      t.string :code
      t.string :group
      t.string :recipe
      t.string :aspect_ratio
      t.integer :duration
      t.string :title
      t.json :concept
      t.boolean :selected, null: false, default: false
      t.string :status
      t.json :spec
      t.json :qa
      t.text :instructions
      t.integer :attempts, null: false, default: 0
      t.text :error

      t.timestamps
    end
  end
end
