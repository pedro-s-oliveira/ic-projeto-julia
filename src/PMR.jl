using JuMP, HiGHS

# Estrutura para armazenar o modelo e o dicionário de restrições
mutable struct RMPStruct
    mdl::Model
    cnst::Dict{Symbol, Any}
end

# ==============================================================================
# PONTO 1: REFORMULAR / ADAPTAR O PMR (Versão Produto Único, Frota Homogênea)
# ==============================================================================
function construir_pmr_base(d_prp)
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    T = d_prp.T
    n_clientes = d_prp.n
    V = d_prp.V # Frota disponível
    # Obs: Os parâmetros M, s, u, h_0, h, d devem vir da sua estrutura d_prp

    # Variáveis de Decisão do Mestre
    @variable(model, 0 <= y[1:T] <= 1)          # Setup relaxado para extrair duais
    @variable(model, p[1:T] >= 0)               # Produção
    @variable(model, I_0[0:T] >= 0)             # Estoque na Fábrica
    @variable(model, I[1:n_clientes, 0:T] >= 0) # Estoque nos Clientes

    # Função Objetivo (Os custos das rotas entram depois com o lambda)
    @objective(model, Min, 
        sum(d_prp.s * y[t] + d_prp.u * p[t] + d_prp.h_0 * I_0[t] for t in 1:T) + 
        sum(d_prp.h[i] * I[i, t] for i in 1:n_clientes, t in 1:T)
    )

    cnst = Dict{Symbol, Any}()

    # Restrições de Produção e Balanço Base
    @constraint(model, cap_producao[t=1:T], p[t] <= d_prp.M[t] * y[t])
    cnst[:balanco_planta] = @constraint(model, [t=1:T], I_0[t] == I_0[t-1] + p[t])
    cnst[:balanco_cliente] = @constraint(model, [i=1:n_clientes, t=1:T], I[i, t] == I[i, t-1] - d_prp.d[i, t])
    
    # Restrições preparadas para receber as rotas (iniciam vazias com AffExpr)
    cnst[:limite_visitas] = @constraint(model, [i=1:n_clientes, t=1:T], AffExpr(0.0) <= 1.0)
    cnst[:limite_veiculos] = @constraint(model, [t=1:T], AffExpr(0.0) <= V)

    return RMPStruct(model, cnst)
end

# ==============================================================================
# PONTO 2: CAPTURAR DUAIS (Separadas rigorosamente por CLIENTE e por PERÍODO)
# ==============================================================================
function extrair_duais_clientes(rmp_struct, d_prp)
    T = d_prp.T
    n_clientes = d_prp.n
    
    # Matrizes [Cliente, Período] para garantir a separação no tempo e no espaço
    delta_dual = zeros(n_clientes, T)
    pi_dual = zeros(n_clientes, T)
    pi_0_dual = zeros(T) # A frota é avaliada apenas por período
    
    for t in 1:T
        pi_0_dual[t] = dual(rmp_struct.cnst[:limite_veiculos][t])
        
        for i in 1:n_clientes
            # A indexação [i, t] garante que o subproblema use o custo marginal exato daquele dia
            delta_dual[i, t] = dual(rmp_struct.cnst[:balanco_cliente][i, t])
            pi_dual[i, t] = dual(rmp_struct.cnst[:limite_visitas][i, t])
        end
    end
    
    return delta_dual, pi_dual, pi_0_dual
end

# ==============================================================================
# PONTO 3: ADICIONAR VARIÁVEL (Encapsulando Percurso e Entregas no Lambda)
# ==============================================================================
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