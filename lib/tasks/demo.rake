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

  desc "Cria um projeto de exemplo do Cabide em awaiting_selection, com o cardápio da fixture (não chama a IA)"
  task cabide_criativos: :environment do
    brief = JSON.parse(File.read(Rails.root.join("test/fixtures/claude/p1_brief.json"), encoding: "UTF-8"))
    menu = JSON.parse(File.read(Rails.root.join("test/fixtures/claude/p3_menu.json"), encoding: "UTF-8"))
    angles = JSON.parse(File.read(Rails.root.join("test/fixtures/claude/p2_angles.json"), encoding: "UTF-8"))
    audience = brief["audiences"].first.merge("source" => "brief")

    # Nunca altera projetos existentes: só cria quando não há um exemplo de cardápio ainda.
    project = Project.where(repo_url: "https://github.com/deyvin/cabide", status: "awaiting_selection").first
    unless project
      project = Project.create!(repo_url: "https://github.com/deyvin/cabide", owner: "deyvin", name: "cabide",
                                status: "awaiting_selection", brief: brief, audience: audience, angles: angles)
      Array(menu["items"]).each do |item|
        project.creatives.create!(code: item["code"], group: item["group"], recipe: item["recipe"],
                                  aspect_ratio: item["aspect_ratio"], duration: item["duration_seconds"],
                                  title: item["title"], concept: item, selected: item["recommended"] == true)
      end
    end
    puts "Cardápio de exemplo (#{project.status}, #{project.creatives.count} criativos): /projects/#{project.id}/creatives"
  end
end
