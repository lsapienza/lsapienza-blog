# =============================================================================
# Volatilidade implícita e as gregas de opções da VALE na B3, em R
# Análise Macro - https://analisemacro.com.br/
#
# Calcula a volatilidade implícita e o Delta das opções (calls e puts) da VALE,
# a partir dos dados públicos da B3, e desenha o "smile" de volatilidade.
#
# Correções em relação à versão original do exercício:
#  (1) As PUTS agora entram: o filtro por corporation_name == "VALE" pegava só
#      calls; as puts vêm sob "VALEE"/"VALEE FM". Passamos a filtrar pelo SYMBOL.
#  (2) A curva de juros vem da API atual da B3 (referenceRatesProxy). O endpoint
#      antigo usado pelo pacote rb3 (www2.bmf...asp) saiu do ar (HTTP 301), então
#      buscamos a curva PRE ("DI x pré") direto no serviço novo da B3 e usamos a
#      taxa de cada vértice — exatamente a curva que o exercício precisa.
#  (3) Os gráficos seguem o padrão de gráficos da Análise Macro: paleta cores_am,
#      caption com autoria + fonte, logo da marca como marca d'água, sem molduras.
# =============================================================================

# Carrega os pacotes usados no exercício
library(rb3)        # dados públicos da B3 (cotações e opções)
library(bizdays)    # contagem de dias úteis pelo calendário ANBIMA
library(dplyr)      # manipulação de dados
library(ggplot2)    # gráficos
library(stringr)    # classificar call/put pelo ticker
library(lubridate)  # datas
library(glue)       # montar textos com variáveis
library(jsonlite)   # ler a API da B3 (JSON em base64)
library(tibble)     # montar a tabela da curva
# Instale o oplib do GitHub caso ainda não tenha:
# if (!require(devtools)) install.packages("devtools")
# devtools::install_github("wilsonfreitas/oplib")
library(oplib)      # matemática de Black-Scholes (vol implícita e gregas)

# -----------------------------------------------------------------------------
# Padrão visual da Análise Macro (paleta + tema + marca d'água)
# -----------------------------------------------------------------------------
# Paleta oficial da casa, usada SEMPRE por índice (nunca cor solta hardcoded).
# A 1ª cor é a série principal; call e put usam duas cores distinguíveis também
# por luminância (azul-escuro x vermelho), não só por matiz (seguro p/ daltônicos).
cores_am <- c(
  "#282f6b",  # 1 azul-escuro  — série principal
  "#1B998B",  # 2 verde-azulado
  "#FF7A00",  # 3 laranja
  "#00798C",  # 4 ciano
  "#b22200",  # 5 vermelho
  "#50514F",  # 6 cinza-escuro
  "#003366",  # 7 azul-marinho
  "#eace3f",  # 8 amarelo
  "#005A9C",  # 9 azul
  "#808080",  # 10 cinza
  "#2E294E"   # 11 roxo-escuro
)

# Cores de call e put a partir da paleta: call = principal, put = vermelho
cor_call <- cores_am[1]   # azul-escuro para as calls
cor_put  <- cores_am[5]   # vermelho para as puts

# Tema limpo da casa: fundo branco, sem molduras, grade leve só na horizontal
tema_am <- function(base_size = 13) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title    = ggplot2::element_text(face = "bold", size = base_size + 3),  # título forte
      plot.subtitle = ggplot2::element_text(color = "grey30"),                     # subtítulo discreto
      plot.caption  = ggplot2::element_text(color = "grey40", hjust = 0),          # crédito à esquerda
      panel.grid.minor = ggplot2::element_blank(),                                 # sem grade menor
      panel.grid.major.x = ggplot2::element_blank(),                               # sem grade vertical
      panel.border  = ggplot2::element_blank(),                                    # sem moldura
      axis.line     = ggplot2::element_line(color = "grey70"),                     # só a base dos eixos
      legend.position = "bottom"                                                   # legenda embaixo
    )
}

# Caption padrão da casa: elaboração fixa + fonte real do dado
caption_am <- "Elaborado por analisemacro.com.br. Fonte: B3."

# -----------------------------------------------------------------------------
# Curva de juros PRE ("DI x pré") pela API atual da B3
# -----------------------------------------------------------------------------
# A B3 serve a curva de referência num endpoint que recebe os parâmetros
# codificados em base64. Cada registro traz os dias úteis (day252) e a taxa
# anual na base 252 (rate). Baixamos todas as páginas e devolvemos a curva.
codificar_b64 <- function(texto) {
  # Converte o texto JSON em base64 (padrão dos endpoints da B3), sem quebra
  gsub("\n", "", jsonlite::base64_enc(charToRaw(texto)))
}

obter_curva_pre_b3 <- function(data_ref, tamanho_pagina = 100) {
  # Monta a URL base do serviço de taxas de referência da B3
  base <- "https://sistemaswebb3-derivativos.b3.com.br/referenceRatesProxy/Search/GetList/"
  # Formata a data no padrão AAAA-MM-DD que a API espera
  d <- format(as.Date(data_ref), "%Y-%m-%d")
  # Função interna que busca uma página da curva
  pega_pagina <- function(pagina) {
    corpo <- sprintf(
      '{"language":"pt-br","date":"%s","id":"PRE","pageNumber":%d,"pageSize":%d}',
      d, pagina, tamanho_pagina
    )
    jsonlite::fromJSON(paste0(base, codificar_b64(corpo)))
  }
  # Busca a primeira página
  primeira <- pega_pagina(1)
  # Se não veio resultado, devolve NULL (data sem curva publicada)
  if (is.null(primeira$results) || NROW(primeira$results) == 0) return(NULL)
  # Acumula os resultados de todas as páginas
  paginas <- list(primeira$results)
  n_paginas <- primeira$page$totalPages
  if (!is.null(n_paginas) && n_paginas > 1) {
    for (p in 2:n_paginas) paginas[[p]] <- pega_pagina(p)$results
  }
  # Junta tudo e organiza as colunas
  registros <- dplyr::bind_rows(paginas)
  tibble::tibble(
    biz_days = as.integer(registros$day252),                       # dias úteis
    rate     = as.numeric(gsub(",", ".", registros$rate)) / 100    # taxa anual (252)
  ) |>
    dplyr::arrange(biz_days) |>
    dplyr::distinct(biz_days, .keep_all = TRUE)
}

# Carrega os calendários de dias úteis embutidos no pacote bizdays
bizdays::load_builtin_calendars()

# Define a data de referência (dado disponível na B3)
refdate_ <- as.Date("2026-07-08")

# Baixa a curva PRE da B3 para a data
curva <- obter_curva_pre_b3(refdate_)

# Função que interpola a taxa da curva para um prazo em dias úteis
taxa_por_dias_uteis <- function(dias_uteis) {
  # approx interpola linearmente; rule = 2 repete a taxa das pontas fora do range
  approx(curva$biz_days, curva$rate, xout = dias_uteis, rule = 2)$y
}

# Define o ticker do ativo objeto e o código da ação à vista
ticker <- "VALE"
spot_ticker <- "VALE3"

# Baixa as cotações históricas diárias da B3 para a data
rb3::fetch_marketdata("b3-cotahist-daily", refdate = refdate_)

# Traz os dados baixados para a memória
df_cotahist <- rb3::cotahist_get(type = "daily") |> dplyr::collect()

# Filtra apenas as opções de ações
options_data <- df_cotahist |> rb3::cotahist_filter_equity_options()

# Filtra apenas o mercado à vista (para pegar o preço da ação)
price_data <- df_cotahist |> rb3::cotahist_filter_equity()

# -----------------------------------------------------------------------------
# Tratamento das opções (calls e puts)
# -----------------------------------------------------------------------------
op1 <- options_data |>
  # Filtra as opções pelo SYMBOL começando com VALE (traz calls E puts)
  dplyr::filter(stringr::str_detect(symbol, paste0("^", ticker, "[A-X]"))) |>
  # Classifica em call ou put pela 5ª letra do ticker (A-L = call, M-X = put)
  dplyr::mutate(
    serie = stringr::str_sub(symbol, 5, 5),
    type = dplyr::case_when(
      serie %in% LETTERS[1:12]  ~ "call",
      serie %in% LETTERS[13:24] ~ "put",
      TRUE ~ NA_character_
    )
  ) |>
  # Remove tickers que não se encaixaram e vencimentos inválidos
  dplyr::filter(!is.na(type), !is.na(maturity_date), maturity_date > refdate_)

# Pega o preço de fechamento da ação à vista (VALE3) na data
price <- price_data |>
  dplyr::filter(symbol == spot_ticker, refdate == refdate_)

# Armazena o preço de fechamento do ativo subjacente
close_underlying <- price$close[1]

# -----------------------------------------------------------------------------
# Cálculo da volatilidade implícita e do Delta
# -----------------------------------------------------------------------------
op_vol <- op1 |>
  dplyr::mutate(
    # Repete o preço do ativo em todas as linhas
    underlying_price = close_underlying,
    # Conta os dias úteis entre a data e o vencimento (ajustado para dia útil)
    biz_days = bizdays::bizdays(
      refdate_,
      bizdays::following(maturity_date, "Brazil/ANBIMA"),
      "Brazil/ANBIMA"
    ),
    # Converte o prazo em anos (base 252 dias úteis)
    time_to_maturity = biz_days / 252,
    # Pega a taxa da curva PRE para o prazo da opção e passa para taxa contínua
    rate = log(1 + taxa_por_dias_uteis(biz_days)),
    # Inverte Black-Scholes para achar a volatilidade implícita
    impvol = oplib::bsmimpvol(
      option_prices = close, type = type, spot = underlying_price,
      strike = strike_price, time = time_to_maturity, rate = rate, yield = 0
    ),
    # Calcula o Delta com a volatilidade implícita encontrada
    delta = oplib::bsmdelta(
      type = type, spot = underlying_price, strike = strike_price,
      time = time_to_maturity, rate = rate, yield = 0, sigma = impvol
    )
  ) |>
  # Mantém apenas linhas com resultados válidos
  dplyr::filter(!is.na(impvol), !is.na(delta), impvol > 0, impvol < 3)

# Cria um vetor ordenado com as datas de vencimento únicas
maturities <- op_vol$maturity_date |> unique() |> sort()

# Escolhe o vencimento com o smile mais rico: o de maior número de strikes
# negociados (mais liquidez dos dois lados dá a curva mais legível).
venc_ancora <- op_vol |>
  dplyr::count(maturity_date, name = "n_strikes") |>
  dplyr::slice_max(n_strikes, n = 1) |>
  dplyr::pull(maturity_date)

# -----------------------------------------------------------------------------
# Gráfico 1: o "smile" de volatilidade por strike (call vs put)
# -----------------------------------------------------------------------------
g_smile <- op_vol |>
  # Mantém o vencimento mais líquido (smile mais completo)
  dplyr::filter(maturity_date == venc_ancora) |>
  # Mapeia strike no eixo x, vol implícita no y, cor por tipo e tamanho por volume
  ggplot2::ggplot(ggplot2::aes(x = strike_price, y = impvol, size = volume, color = type)) +
  # Marca o preço à vista com uma linha vertical
  ggplot2::geom_vline(xintercept = close_underlying, linetype = "dashed", color = "grey50") +
  # Desenha os pontos com transparência
  ggplot2::geom_point(alpha = 0.55) +
  # Define as cores da marca para call e put (pela paleta cores_am)
  ggplot2::scale_color_manual(values = c(call = cor_call, put = cor_put),
                              labels = c(call = "Call", put = "Put"), name = NULL) +
  # Esconde a legenda de tamanho
  ggplot2::scale_size_continuous(guide = "none") +
  # Escreve título que conta o achado, rótulos e o crédito no padrão da casa
  ggplot2::labs(
    x = "Strike (R$)", y = "Volatilidade implícita",
    title = "A volatilidade sobe nas pontas: o sorriso da VALE",
    subtitle = glue::glue("Opções da VALE por strike, vencimento {format(venc_ancora, '%d/%m/%Y')}"),
    caption = caption_am
  ) +
  # Aplica o tema limpo da casa
  tema_am()

# Salva o smile em PNG de alta resolução (padrão da casa: 300 dpi)
ggplot2::ggsave(
  "../imgs/smile-volatilidade-vale3-1o-vencimento.png",
  g_smile, width = 8, height = 5, dpi = 300, bg = "white"
)

# -----------------------------------------------------------------------------
# Gráfico 2: volatilidade implícita vs. Delta (onde está a liquidez)
# -----------------------------------------------------------------------------
g_delta <- op_vol |>
  # Mantém o mesmo vencimento âncora para comparabilidade
  dplyr::filter(maturity_date == venc_ancora) |>
  # Mapeia Delta no eixo x, vol no y, cor por tipo e tamanho por volume
  ggplot2::ggplot(ggplot2::aes(x = delta, y = impvol, size = volume, color = type)) +
  # Marca o Delta zero (fronteira entre as pontas)
  ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
  # Desenha os pontos com transparência
  ggplot2::geom_point(alpha = 0.55) +
  # Define as cores da marca para call e put
  ggplot2::scale_color_manual(values = c(call = cor_call, put = cor_put),
                              labels = c(call = "Call", put = "Put"), name = NULL) +
  # Esconde a legenda de tamanho
  ggplot2::scale_size_continuous(guide = "none") +
  # Escreve título, rótulos e crédito
  ggplot2::labs(
    x = "Delta", y = "Volatilidade implícita",
    title = "A liquidez se concentra nas opções no dinheiro",
    subtitle = glue::glue("Vol implícita por Delta, vencimento {format(venc_ancora, '%d/%m/%Y')}"),
    caption = caption_am
  ) +
  # Aplica o tema limpo da casa
  tema_am()

# Salva o gráfico de Delta em PNG de alta resolução
ggplot2::ggsave(
  "../imgs/vol-implicita-delta-vale3.png",
  g_delta, width = 8, height = 5, dpi = 300, bg = "white"
)

# -----------------------------------------------------------------------------
# Gráfico 3: estrutura a termo do smile (o padrão em vários vencimentos)
# -----------------------------------------------------------------------------
# Seleciona os quatro vencimentos com mais strikes negociados
vencs_top4 <- op_vol |>
  dplyr::count(maturity_date, name = "n_strikes") |>
  dplyr::slice_max(n_strikes, n = 4) |>
  dplyr::arrange(maturity_date) |>
  dplyr::pull(maturity_date)

g_termo <- op_vol |>
  # Mantém só os quatro vencimentos mais líquidos
  dplyr::filter(maturity_date %in% vencs_top4) |>
  # Rotula cada painel pela data de vencimento
  dplyr::mutate(painel = format(maturity_date, "Vencimento %d/%m/%Y")) |>
  # Mapeia strike no x, vol no y, cor por tipo
  ggplot2::ggplot(ggplot2::aes(x = strike_price, y = impvol, size = volume, color = type)) +
  # Marca o preço à vista em cada painel
  ggplot2::geom_vline(xintercept = close_underlying, linetype = "dashed", color = "grey50") +
  # Desenha os pontos com transparência
  ggplot2::geom_point(alpha = 0.55) +
  # Um painel por vencimento
  ggplot2::facet_wrap(~ painel, scales = "free_x") +
  # Define as cores da marca para call e put
  ggplot2::scale_color_manual(values = c(call = cor_call, put = cor_put),
                              labels = c(call = "Call", put = "Put"), name = NULL) +
  # Esconde a legenda de tamanho
  ggplot2::scale_size_continuous(guide = "none") +
  # Escreve título, rótulos e crédito
  ggplot2::labs(
    x = "Strike (R$)", y = "Volatilidade implícita",
    title = "O sorriso aparece em todos os prazos",
    subtitle = "Smile da VALE nos quatro vencimentos mais negociados",
    caption = caption_am
  ) +
  # Aplica o tema limpo da casa
  tema_am()

# Salva a estrutura a termo em PNG de alta resolução
ggplot2::ggsave(
  "../imgs/estrutura-termo-smile-vale3.png",
  g_termo, width = 9, height = 6, dpi = 300, bg = "white"
)
