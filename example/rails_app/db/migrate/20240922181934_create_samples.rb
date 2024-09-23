class CreateSamples < ActiveRecord::Migration[7.2]
  def change
    create_table :samples do |t|
      t.string :name

      t.timestamps
    end
  end
end
