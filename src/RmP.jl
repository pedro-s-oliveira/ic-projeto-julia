# modulo para tratar o problema mestre restrito (PMR/RMP/Restricted master problem)
module Rmp
    using JuMP
    using HiGHS
    include("DaTA.jl") 
    using .Dados
    
    mutable struct mp
        mdl::Model                                
        nome::String                              
        vars::Dict{Symbol, Any}                   
        obj::Union{JuMP.GenericAffExpr, Nothing}  
        cnst::Dict{Symbol, Any}                   
        fs::Union{Nothing, Dict{Symbol, Float64}} 
        
        function mp(nome::String="rmp")
            mdl = Model(HiGHS.Optimizer)
            set_silent(mdl)
            set_optimizer_attribute(mdl, "output_flag", false)  
            vars = Dict{Symbol, Any}()
            cnst = Dict{Symbol, Any}()
            new(mdl, nome, vars, nothing, cnst, nothing)
        end
    end

    # Métodos genéricos
    function adicionar_restricao!(m::mp, nome::Symbol, expressao)
        constr_ref = add_constraint(m.mdl, expressao)
        m.cnst[nome] = constr_ref
        return constr_ref
    end

    # =========================================================================
    # LÓGICA DO PROBLEMA MESTRE RESTRITO (RMP) - Adulyasak (2015)
    # =========================================================================
    function createRMP(d_prp)
        rmp = mp("Problema_Mestre_Restrito")
        model = rmp.mdl

        T = d_prp.T
        clientes = 1:d_prp.n
        n_clientes = d_prp.n
        deposito = 0

        # -------------------------------------------------------------------------
        # VARIÁVEIS
        # -------------------------------------------------------------------------
        @variable(model, p[1:T] >= 0)
        @variable(model, I[0:n_clientes, 0:T] >= 0)
        @variable(model, 0 <= y[1:T] <= 1)
        
        # Variáveis Artificiais (Sigma) para garantir a viabilidade inicial (Big-M)
        @variable(model, sigma_planta[1:T] >= 0)
        @variable(model, sigma_cliente[clientes, 1:T] >= 0)

        # -------------------------------------------------------------------------
        # FUNÇÃO OBJETIVO
        # -------------------------------------------------------------------------
        rmp.obj = @objective(model, Min,
            sum(d_prp.u * p[t] + d_prp.f * y[t] for t in 1:T) +                
            sum(d_prp.h[1] * I[deposito, t] for t in 1:T) +                    
            sum(d_prp.h[i] * I[i, t] for i in clientes, t in 1:T) +            
            1e5 * sum(sigma_planta[t] for t in 1:T) +   # Multa menor na fábrica (100 mil)
            1e7 * sum(sigma_cliente[i, t] for i in clientes, t in 1:T) # Multa maior nos clientes (10 milhões)
        )
        
        # -------------------------------------------------------------------------
        # RESTRIÇÕES
        # -------------------------------------------------------------------------
        # Estoque inicial fixado em 0 para todos os nós
        for i in 0:n_clientes
            fix(I[i, 0], 0.0, force=true) 
        end

        # (35) Balanço de Estoque na Fábrica 
        rmp.cnst[:balanco_planta] = @constraint(model, [t=1:T],
            I[deposito, t-1] + p[t] + sigma_planta[t] == I[deposito, t]
        )

        # (36) Balanço de Estoque nos Clientes
        rmp.cnst[:balanco_cliente] = @constraint(model, [i=clientes, t=1:T],
            I[i, t-1] + sigma_cliente[i, t] == d_prp.d[i, t] + I[i, t]
        )

        # Restrição de Limite de Veículos por período 
        # Travado temporariamente em 7.0 até que d_prp.V seja injetado
        rmp.cnst[:limite_veiculos] = @constraint(model, [t=1:T],
            0.0 <= 7.0
        )

        # Restrições de Capacidade de Produção
        rmp.cnst[:capacidade_producao] = @constraint(model, [t=1:T],
            p[t] <= d_prp.C * y[t]
        )

        return rmp
    end

end 