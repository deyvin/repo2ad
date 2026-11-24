namespace :demo do
  desc "Cria o projeto de exemplo do Cabide em awaiting_audience, com o brief da fixture (não chama a IA)"
  task cabide: :environment do
    brief = JSON.parse(File.read(Rails.root.join("test/fixtures/claude/p1_brief.json"), encoding: "UTF-8"))
    # Reaproveita um exemplo que ainda esteja em awaiting_audience; nunca altera projetos existentes.
    project = Project.where(repo_url: "https://github.com/deyvin/cabide", status: "awaiting_audience").first ||
              Project.create!(repo_url: "https://github.com/deyvin/cabide", owner: "deyvin", name: "cabide",
                              status: "awaiting_audience", brief: brief)
    puts "Projeto de exemplo (#{project.status}): /projects/#{project.id}/audience"
  end
end
