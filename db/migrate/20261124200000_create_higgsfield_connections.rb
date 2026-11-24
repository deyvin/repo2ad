class CreateHiggsfieldConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :higgsfield_connections do |t|
      t.text :client_information
      t.text :tokens
      t.text :pending
      t.datetime :connected_at

      t.timestamps
    end
  end
end
