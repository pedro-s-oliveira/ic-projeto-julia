#Algoritmo totalmente experimental para o problema da mochila com frota heterogênea (capacidade diferente para cada caminhão) e itens limitados (Bounded Knapsack).
module MochilaFrota

using JuMP
using HiGHS

export carregar_caminhoes

# Função universal do Problema da Mochila adaptada para frota heterogênea
function carregar_caminhoes(valores::Vector{Float64}, pesos::Vector{Float64}, capacidades_caminhoes::Vector{Int}, limites_itens::Vector{Int})
    # valores: Lucro ou preço dual de cada item/demanda
    # pesos: Peso ou volume de cada item/demanda
    # capacidades_caminhoes: Vetor com a capacidade de cada caminhão da frota (frota heterogênea)
    # limites_itens: Quantidade máxima disponível de cada item (Bounded Knapsack)

    modelo = Model(HiGHS.Optimizer)
    set_silent(modelo)

    num_itens = length(valores)
    num_caminhoes = length(capacidades_caminhoes)

    # ---------------------------------------------------------
    # VARIÁVEL DE DECISÃO
    # ---------------------------------------------------------
    # q[i, v] = Quantidade do item i colocada no caminhão v
    @variable(modelo, q[1:num_itens, 1:num_caminhoes] >= 0, Int)

    # ---------------------------------------------------------
    # FUNÇÃO OBJETIVO
    # ---------------------------------------------------------
    # Maximizar o valor (lucro/preço dual) dos itens carregados
    @objective(modelo, Max, 
        sum(valores[i] * q[i, v] for i in 1:num_itens, v in 1:num_caminhoes)
    )

    # ---------------------------------------------------------
    # RESTRIÇÕES
    # ---------------------------------------------------------
    # 1. Respeitar a capacidade (heterogênea) de cada caminhão individualmente
    @constraint(modelo, [v in 1:num_caminhoes], 
        sum(pesos[i] * q[i, v] for i in 1:num_itens) <= capacidades_caminhoes[v]
    )

    # 2. Respeitar o limite disponível de cada item (não carregar mais do que existe)
    @constraint(modelo, [i in 1:num_itens], 
        sum(q[i, v] for v in 1:num_caminhoes) <= limites_itens[i]
    )

    # ---------------------------------------------------------
    # RESOLUÇÃO
    # ---------------------------------------------------------
    optimize!(modelo)

    if termination_status(modelo) == MOI.OPTIMAL
        valor_total = objective_value(modelo)
        alocacao = value.(q)
        
        println("=> Carregamento Concluído! Valor total obtido: ", round(valor_total, digits=2))
        
        for v in 1:num_caminhoes
            peso_usado = 0.0
            println("\n--- Caminhão $v (Capacidade Máx: $(capacidades_caminhoes[v])) ---")
            for i in 1:num_itens
                qtd = Int(round(alocacao[i, v]))
                if qtd > 0
                    println("  Item $i: $qtd unidades carregadas (Peso Total: $(qtd * pesos[i]))")
                    peso_usado += qtd * pesos[i]
                end
            end
            println("  -> Espaço Ocupado: $peso_usado / $(capacidades_caminhoes[v])")
        end
        
        return valor_total, alocacao
    else
        println("O solver não encontrou uma solução viável.")
        return nothing, nothing
    end
end

end # module