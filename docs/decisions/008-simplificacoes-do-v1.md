# 008: Simplificações do v1 (demonstração)

Data: 2026-11-24. Decisão do usuário: o Repo2Ad é um projeto de **demonstração**.

## 1. Segurança não é critério de aceite
- Não há mais hardening nem testes de segurança: SSRF, tar bombs, path traversal, CSRF, criptografia e auditoria de log.
  O que já foi feito fica como está; não se cria mais nada nem se reprova por isso.
- Continua valendo (regra do usuário): chaves só no `.env`, que nunca é commitado.
- Continua valendo: testes sem rede (fakes) e sem gastar créditos.

## 2. QA por risco
- O QA Rubycheck testa a fundo só **telas novas** (como um usuário, no navegador) e o que **gasta créditos**
  (gerações e custos).
- Correções pequenas e serviços internos: o CTO revisa o diff e confere a evidência do dev.

## 3. Paralelizar com dados falsos
- As telas de público (T5), de criativos (T6) e de resultado (TR) são feitas com dados de exemplo no banco
  (brief, ângulos e criativos fictícios do Cabide), sem esperar as etapas de IA. A ligação com P2/P3 entra depois da T4.

## 4. Corte de escopo
- A receita `kling_magic` não tem implementação própria no v1: o §6.3 diz que o contrato é o mesmo da `kling_reference`.
  Um item do cardápio com `kling_magic` é executado pelo pipeline da `kling_reference`, com o prompt que o P4 gerar.
  Sem exemplo, teste ou ajuste dedicado.
- T12 (legendas com ffmpeg) sai do v1.
