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
function adicionar_coluna_prp!(rmp_struct, d_prp, t, entregas, z_ir, custo_rota)
    model = rmp_struct.mdl
    
    theta = @variable(model, lower_bound=0.0, upper_bound=1.0)
    set_objective_coefficient(model, theta, custo_rota)
    
    # Impacto Global na Fábrica: Caminhão RETIRA produtos (Sinal Negativo)
    total_entregue = sum(entregas)
    if total_entregue > 0
        set_normalized_coefficient(rmp_struct.cnst[:balanco_planta][t], theta, -Float64(total_entregue))
    end
    
    # Impacto Específico no Cliente: Caminhão ENTREGA produtos (Sinal Positivo)
    for i in 1:d_prp.n
        if entregas[i] > 0 || z_ir[i] > 0
            
            # Injeta a quantidade no balanço do cliente
            set_normalized_coefficient(rmp_struct.cnst[:balanco_cliente][i, t], theta, Float64(entregas[i]))
            
            # Injeta a visita no limite de visitas do cliente
            set_normalized_coefficient(rmp_struct.cnst[:limite_visitas][i, t], theta, Float64(z_ir[i]))
        end
    end
    
    set_normalized_coefficient(rmp_struct.cnst[:limite_veiculos][t], theta, 1.0)
end

#=

function extract_duals(rmp_struct, d_prp)
    model = rmp_struct.mdl
    T, n_clientes = d_prp.T, d_prp.n
    alpha1, alpha3 = zeros(T), zeros(T)
    alpha2 = zeros(n_clientes + 2, T)
    
    if has_duals(model)
        for t in 1:T
            alpha1[t] = dual(rmp_struct.cnst[:balanco_planta][t])
            alpha3[t] = dual(rmp_struct.cnst[:limite_veiculos][t])
            for i in 1:n_clientes
                alpha2[i + 1, t] = dual(rmp_struct.cnst[:balanco_cliente][i, t])
            end
        end
    end
    return alpha1, alpha2, alpha3
end

function adicionar_coluna_prp!(rmp_struct, d_prp, t, entregas, custo_rota)
    model = rmp_struct.mdl
    theta = @variable(model, lower_bound=0.0, upper_bound=1.0)
    
    set_objective_coefficient(model, theta, custo_rota)
    
    total_entregue = sum(entregas)
    if total_entregue > 0
        set_normalized_coefficient(rmp_struct.cnst[:balanco_planta][t], theta, -Float64(total_entregue))
    end
    
    for i in 2:(d_prp.n + 1)
        if entregas[i] > 0
            set_normalized_coefficient(rmp_struct.cnst[:balanco_cliente][i - 1, t], theta, Float64(entregas[i]))
        end
    end
    
    set_normalized_coefficient(rmp_struct.cnst[:limite_veiculos][t], theta, 1.0)
end

=#