using JuMP, HiGHS

# ---------------------------------------------------------
# 1. AS FUNÇÕES DO PMR (Agora com a variável SIGMA incluída)
# ---------------------------------------------------------
mutable struct RMPStruct
    mdl::Model
    cnst::Dict{Symbol, Any}
end

function construir_pmr_base(d_prp)
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    T = d_prp.T; n_clientes = d_prp.n; V = d_prp.V

    # Variáveis Reais
    @variable(model, 0 <= y[1:T] <= 1)
    @variable(model, p[1:T] >= 0)
    @variable(model, I_0[0:T] >= 0)
    @variable(model, I[1:n_clientes, 0:T] >= 0)

    fix(I_0[0], 0.0; force=true)
    for i in 1:n_clientes
        fix(I[i, 0], 0.0; force=true)
    end
    
    # VARIÁVEIS ARTIFICIAIS (SIGMA) PARA EVITAR INVIABILIDADE NA ITERAÇÃO 0
    @variable(model, sigma_planta[1:T] >= 0)
    @variable(model, sigma_cliente[1:n_clientes, 1:T] >= 0)
    custo_M = 1_000_000.0 # O Big-M para forçar o sigma a sumir depois

    @objective(model, Min, 
        sum(d_prp.s * y[t] + d_prp.u * p[t] + d_prp.h_0 * I_0[t] for t in 1:T) + 
        sum(d_prp.h[i] * I[i, t] for i in 1:n_clientes, t in 1:T) +
        sum(custo_M * sigma_planta[t] for t in 1:T) +
        sum(custo_M * sigma_cliente[i, t] for i in 1:n_clientes, t in 1:T)
    )

    cnst = Dict{Symbol, Any}()

    @constraint(model, cap_producao[t=1:T], p[t] <= d_prp.M[t] * y[t])
    
    # Sigmas injetados no balanço inicial
    cnst[:balanco_planta] = @constraint(model, [t=1:T], I_0[t] == I_0[t-1] + p[t] - sigma_planta[t])
    cnst[:balanco_cliente] = @constraint(model, [i=1:n_clientes, t=1:T], I[i, t] == I[i, t-1] - d_prp.d[i, t] + sigma_cliente[i, t])
    
    cnst[:limite_visitas] = @constraint(model, [i=1:n_clientes, t=1:T], AffExpr(0.0) <= 1.0)
    cnst[:limite_veiculos] = @constraint(model, [t=1:T], AffExpr(0.0) <= V)

    return RMPStruct(model, cnst)
end

function extrair_duais_clientes(rmp_struct, d_prp)
    delta_dual = zeros(d_prp.n, d_prp.T)
    pi_dual = zeros(d_prp.n, d_prp.T)
    for t in 1:d_prp.T
        for i in 1:d_prp.n
            delta_dual[i, t] = dual(rmp_struct.cnst[:balanco_cliente][i, t])
            pi_dual[i, t] = dual(rmp_struct.cnst[:limite_visitas][i, t])
        end
    end
    return delta_dual, pi_dual
end

function adicionar_coluna_prp!(rmp_struct, d_prp, t, entregas, custo_rota)
    model = rmp_struct.mdl
    
    theta = @variable(model, lower_bound=0.0, upper_bound=1.0)
    set_objective_coefficient(model, theta, custo_rota)
    
    total_entregue = sum(entregas)
    if total_entregue > 0
        # MUDANÇA 1 AQUI: Ficou POSITIVO (removido o sinal de menos)
        set_normalized_coefficient(rmp_struct.cnst[:balanco_planta][t], theta, Float64(total_entregue))
    end
    
    for i in 2:(d_prp.n + 1)
        if entregas[i] > 0
            cliente_id = i - 1
            
            # MUDANÇA 2 AQUI: Ficou NEGATIVO (adicionado o sinal de menos)
            set_normalized_coefficient(rmp_struct.cnst[:balanco_cliente][cliente_id, t], theta, -Float64(entregas[i]))
            
            set_normalized_coefficient(rmp_struct.cnst[:limite_visitas][cliente_id, t], theta, 1.0)
        end
    end
    
    set_normalized_coefficient(rmp_struct.cnst[:limite_veiculos][t], theta, 1.0)
end

# ---------------------------------------------------------
# 2. A EXECUÇÃO DO TESTE (Aqui a mágica acontece)
# ---------------------------------------------------------

# Criando dados fictícios (Mock) usando NamedTuple
d_prp_teste = (
    T = 2, n = 2, V = 2, 
    M = [100.0, 100.0], s = 500.0, u = 10.0, h_0 = 2.0, 
    h = [3.0, 4.0], 
    d = [10.0 15.0; 20.0 25.0] # Demanda dos 2 clientes em 2 dias
)

println("\n--- INICIANDO TESTE ISOLADO DO PMR ---")

println("\n1. Construindo o PMR...")
meu_pmr = construir_pmr_base(d_prp_teste)

println("\n2. Resolvendo Iteração 0 (Somente com Sigmas)...")
optimize!(meu_pmr.mdl)
println("Status do Solver: ", termination_status(meu_pmr.mdl))
println("Custo Total: R\$ ", objective_value(meu_pmr.mdl))

println("\n3. Extraindo Duais do Cliente...")
duais_delta, duais_pi = extrair_duais_clientes(meu_pmr, d_prp_teste)
println("Duais de Balanço (Delta):")
display(duais_delta)

println("\n4. Subproblema achou uma rota fantástica! Adicionando variável Lambda...")
# Simulando: Rota no período 1, custou R$ 50.0, entregou 0 no depósito, 10 no C1 e 20 no C2
entregas_simuladas = [0.0, 10.0, 20.0] 
adicionar_coluna_prp!(meu_pmr, d_prp_teste, 1, entregas_simuladas, 50.0)

println("\n5. Resolvendo Iteração 1 (Com a Nova Rota Lambda)...")
optimize!(meu_pmr.mdl)
println("Status do Solver: ", termination_status(meu_pmr.mdl))
println("Novo Custo Total: R\$ ", objective_value(meu_pmr.mdl))
println("--------------------------------------\n")