class AddIgnoredUploadsToProjects < ActiveRecord::Migration[8.1]
  def change
    # Nomes das fotos enviadas que não abriram como imagem e foram ignoradas (com aviso na tela de análise).
    add_column :projects, :ignored_uploads, :json
  end
end
