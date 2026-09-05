# renv: pula o autoloader dentro do sandbox do Codex (2026-09-04).
# O sandbox nega escrita fora do projeto e o renv entra em loop infinito
# tentando criar diretorios em ~/Library/Caches. Fora do sandbox nada muda.
if (nzchar(Sys.getenv("CODEX_SANDBOX"))) {
  message("renv: autoloader pulado dentro do sandbox do Codex")
} else {
  source("renv/activate.R")
}
