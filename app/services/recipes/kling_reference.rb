module Recipes
  # §6.2: quadro inicial já no aspecto final (D6) e vídeo do Kling a partir dele, com até 4 referências do produto.
  # O quadro inicial vem do Nano Banana (cena nova ou foto real com as bordas estendidas, outpaint pedido no prompt)
  # ou de um compose local. A kling_magic (§6.3) usa este mesmo pipeline (decisão 008).
  class KlingReference < Base
    STEPS = [ [ %w[start_frame nano_banana], %w[main kling] ], [ %w[start_frame compose], %w[main kling] ] ].freeze
    MAX_PRODUCT_REFERENCES = 4
  end
end
