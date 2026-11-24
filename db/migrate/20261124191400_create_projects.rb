class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :repo_url
      t.string :owner
      t.string :name
      t.string :commit_sha
      t.string :status
      t.json :brief
      t.json :audience
      t.json :angles
      t.text :error

      t.timestamps
    end
  end
end
