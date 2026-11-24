require "vips"
require_relative "fake_claude"

# Projeto Cabide pronto para gerar: brief gravado (P1), um ângulo, mídias (galeria.png real e fotos sintéticas)
# e os criativos I1 (nb_image), H1 (kling_keyframes) e V3 (kling_reference) do §12. Sem rede.
module CreativeFixtures
  ANGLE = { "key" => "antes_depois", "name" => "Antes e depois", "hook" => "Tirei no chão do quarto.",
            "support_line" => "Virou foto de loja.", "proof" => "galeria.png", "cta_label" => "Ver no GitHub",
            "primary" => true }.freeze

  def create_cabide_project
    project = Project.create!(repo_url: "https://github.com/deyvin/cabide", owner: "deyvin", name: "cabide",
                              brief: JSON.parse(FakeClaude.fixture("p1_brief")),
                              angles: { "audience_summary" => "pequenos vendedores de moda", "angles" => [ ANGLE ] })
    attach_media(project, "docs/screenshots/galeria.png", "repo", "screenshot", file_fixture("galeria.png").to_s)
    attach_media(project, "uploads/chao.jpg", "upload", "photo", synthetic("chao.jpg", 900, 1200, [ 236, 236, 240 ]))
    attach_media(project, "uploads/catalogo.png", "upload", "photo", synthetic("catalogo.png", 1024, 1024, [ 250, 250, 250 ]))
    project
  end

  def create_creative(project, code)
    attrs = {
      "I1" => { group: "image", recipe: "nb_image", aspect_ratio: "4:5", duration: nil,
                media: %w[uploads/chao.jpg uploads/catalogo.png] },
      "H1" => { group: "horizontal", recipe: "kling_keyframes", aspect_ratio: "16:9", duration: 10,
                media: %w[docs/screenshots/galeria.png uploads/chao.jpg uploads/catalogo.png] },
      "V3" => { group: "vertical", recipe: "kling_reference", aspect_ratio: "9:16", duration: 10,
                media: %w[uploads/chao.jpg uploads/catalogo.png] }
    }.fetch(code)
    item = { "code" => code, "group" => attrs[:group], "recipe" => attrs[:recipe], "title" => "#{code} do teste",
             "aspect_ratio" => attrs[:aspect_ratio], "duration_seconds" => attrs[:duration], "angle_key" => "antes_depois",
             "concept" => "conceito do #{code}", "beats" => [], "media_paths" => attrs[:media],
             "needs_user_media" => nil, "caption_overlay" => nil, "recommended" => true }
    project.creatives.create!(code: code, group: attrs[:group], recipe: attrs[:recipe], aspect_ratio: attrs[:aspect_ratio],
                              duration: attrs[:duration], title: item["title"], concept: item, selected: true, status: "queued")
  end

  def p4_fixture(code) = JSON.parse(FakeClaude.fixture("p4_#{code.downcase}"))

  private

  def attach_media(project, path, source, kind, file)
    media = project.media_inputs.create!(path: path, source: source, kind: kind, description: path)
    image = Vips::Image.new_from_file(file)
    media.update!(width: image.width, height: image.height)
    File.open(file, "rb") { media.file.attach(io: _1, filename: File.basename(file)) }
  end

  def synthetic(name, width, height, rgb)
    @media_dir ||= Dir.mktmpdir("creative-fixtures")
    path = File.join(@media_dir, name)
    Vips::Image.black(width, height).new_from_image(rgb).cast(:uchar).copy(interpretation: :srgb).write_to_file(path)
    path
  end
end
