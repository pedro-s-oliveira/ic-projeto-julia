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
            # Correção dos nomes internos da struct
            new(mdl, nome, vars, nothing, cnst, nothing)
        end
    end

    # Métodos genéricos do professor
    function adicionar_restricao!(m::mp, nome::Symbol, expressao)
        constr_ref = add_constraint(m.mdl, expressao)
        m.cnst[nome] = constr_ref
        return constr_ref
    end

    # =========================================================================
    # LÓGICA DO PROBLEMA MESTRE RESTRITO (RMP) - Adulyasak (2015)
    # =========================================================================
    function createRMP(d_prp) 
        println("Criando PMR para o Problema de Roteamento de Produção...")
        rmp = mp("RMP_Producao")
        model = rmp.mdl 
        
        T = d_prp.T
        n_clientes = d_prp.n
        clientes = 2:(n_clientes + 1)
        deposito = 1
        
        # Variáveis Originais (34-38)
        @variable(model, p[1:T] >= 0)                   
        @variable(model, I[1:(n_clientes+1), 0:T] >= 0) 
        @variable(model, 0 <= y[1:T] <= 1)              
        @variable(model, art_plant[1:T] >= 0)
        @variable(model, art_cust[clientes, 1:T] >= 0)

        # Função Objetivo (34)
        @objective(model, Min, 
            sum(d_prp.u * p[t] + d_prp.f * y[t] for t in 1:T) +                
            sum(d_prp.h[1] * I[deposito, t] for t in 1:T) +                    
            sum(d_prp.h[i] * I[i, t] for i in clientes, t in 1:T) +            
            1e7 * (sum(art_plant[t] for t in 1:T) + sum(art_cust[i, t] for i in clientes, t in 1:T)) 
        )
        
        # Estoque inicial fixado em 0 (ajustável se d_prp.I0 for usado)
        for i in 1:(n_clientes+1)
            fix(I[i, 0], 0.0, force=true) 
        end

        # (35) Balanço de Estoque na Fábrica
        rmp.cnst[:balanco_planta] = @constraint(model, [t=1:T],
            I[deposito, t-1] + p[t] + art_plant[t] == I[deposito, t]
        )

        # (36) Balanço de Estoque nos Clientes
        rmp.cnst[:balanco_cliente] = @constraint(model, [i=clientes, t=1:T],
            I[i, t-1] + art_cust[i, t] == d_prp.d[i, t] + I[i, t]
        )

        # (37) Seleção de plano de entrega
        rmp.cnst[:selecao_plano] = @constraint(model, [t=1:T], 0.0 <= 1.0)

        # Restrições de Capacidade (4, 5, 6)
        @constraint(model, [t=1:T], p[t] <= d_prp.C * y[t])
        @constraint(model, [t=1:T], I[deposito, t] <= d_prp.L[deposito])
        @constraint(model, [i=clientes, t=1:T], I[i, t] <= d_prp.L[i])
    
        return rmp
    end
end