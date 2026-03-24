module TesteBrinquedo

include("DaTA.jl")
include("PRP_Relaxado_Cap2.jl")

using .Dados
using .PRP_Relaxado_Cap2

function rodar_toy_instance()
    println("Montando a Instancia Brinquedo...")
    d = Dados.dados()
    
    # Tamanho do problema
    d.n = 1  # 1 Cliente
    d.T = 2  # 2 Periodos
    d.P = 1  # 1 Produto
    d.V = 1  # 1 Veiculo

    # Produção (Capacidade, custo unitario, custo setup)
    d.C = Dict(1 => 100)
    d.u = Dict(1 => 10.0)
    d.l = Dict(1 => 50.0)

    # Veículo
    d.Q = Dict(1 => 50) 
    d.e = Dict(1 => 0.0)

    # Distâncias (Planta fica no y=0, Cliente no y=100)
    d.x = Dict(0 => 0.0, 1 => 0.0)
    d.y = Dict(0 => 0.0, 1 => 100.0)
    d.A = Set([(0,1), (1,0)]) # Ida e volta

    # Inventário
    d.I0 = Dict((0,1) => 0, (1,1) => 0) 
    d.U  = Dict((0,1) => 100, (1,1) => 100)
    d.h  = Dict((0,1) => 1.0, (1,1) => 2.0)

    # Demanda (cliente, produto, periodo)
    d.d = Dict(
        (1, 1, 1) => 10,
        (1, 1, 2) => 20
    )

    println("Instancia criada! Resolvendo o modelo...")
    
    # Chamamos com o prefixo do módulo para não ter NENHUMA ambiguidade!
    lb = PRP_Relaxado_Cap2.resolver_modelo_221_relaxado(d)
    
    println("\n--- RESULTADO ESPERADO VS OBTIDO ---")
    println("O custo para fabricar 30 caixas a R\$ 10 e R\$ 300.")
    println("O modelo vai usar setup fracionario e frete fracionario para as 30 caixas.")
    println("Limite Inferior esperado rondando os ~ R\$ 633.00")
    println("Lower Bound retornado pelo Julia: R\$ ", round(lb, digits=2))
end

# Executa protegendo contra o World Age
Base.invokelatest(rodar_toy_instance)

end # module