class CreateRenderSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :render_steps do |t|
      t.references :creative, null: false, foreign_key: true
      t.string :name
      t.string :kind
      t.string :model
      t.json :params
      t.string :hf_job_id
      t.string :status
      t.integer :poll_attempts, null: false, default: 0
      t.text :error

      t.timestamps
    end
  end
end
