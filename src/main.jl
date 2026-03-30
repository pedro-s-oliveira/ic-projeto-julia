# O ponto de entrada do projeto
module MeuProjeto

include("calculos.jl")
include("DaTA.jl")                 
include("PRP_Relaxado_Cap2.jl")  

using .Dados               
using .PRP_Relaxado_Cap2          

function executar()
    # Seu código original
    qtd = 150
    preco = 12.50
    total = calcular_custo_total(qtd, preco)
    println("O custo total da producao e: ", formatar_moeda(total))

    # O nosso código
    println("--------------------------------------------------")
    println("Localizando e lendo a instância ABS2_50_6.dat...")

    caminho_arquivo = joinpath(@__DIR__, "ABS2_50_6.dat")
    dados_instancia = Dados.dados()
    Dados.leitura(dados_instancia, caminho_arquivo)

    println("Dados carregados! Resolvendo modelo compacto relaxado (Cap 2.2.1)...")

    # A chamada ao modelo está protegida aqui dentro!
    lb_relaxado = resolver_modelo_221_relaxado(dados_instancia)

    println("--------------------------------------------------")
end

# Isso invoca a sua função sem causar o erro de World Age
Base.invokelatest(executar)

end