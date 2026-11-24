# Receitas fixas de geração (§6, D7). O P4 preenche o spec; a receita executa os steps em ordem.
module Recipes
  class Error < StandardError; end

  IMPLEMENTED = { "nb_image" => "Recipes::NbImage", "kling_keyframes" => "Recipes::KlingKeyframes" }.freeze

  def self.for(recipe)
    name = IMPLEMENTED[recipe.to_s] or raise Error, "a receita #{recipe} ainda não está disponível (T10)"
    name.constantize
  end
end
