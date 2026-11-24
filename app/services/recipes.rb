# Receitas fixas de geração (§6, D7). O P4 preenche o spec; a receita executa os steps em ordem.
module Recipes
  class Error < StandardError; end

  IMPLEMENTED = {
    "nb_image" => "Recipes::NbImage",
    "kling_keyframes" => "Recipes::KlingKeyframes",
    "kling_reference" => "Recipes::KlingReference",
    "kling_magic" => "Recipes::KlingReference" # decisão 008: mesmo pipeline, com o contrato da kling_magic no P4
  }.freeze

  def self.for(recipe)
    name = IMPLEMENTED[recipe.to_s] or raise Error, "receita desconhecida: #{recipe}"
    name.constantize
  end
end
