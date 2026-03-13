#modulo para tratar o problema mestre restrito (PMR/RMP/Restricted master problem)
module Rmp
    using JuMP
    using HiGHS
    #modulo para leitura e impressao de dados
    include("DaTA.jl") 
    using .Dados
    
    
    # Estrutura principal para um problema de programação linear
    mutable struct mp
        mdl::Model                                # Modelo JuMP
        nome::String                              # Nome do problema
        vars::Dict{Symbol, VariableRef}           # Dicionário de variáveis
        obj::Union{JuMP.GenericAffExpr, Nothing}  # Expressão da função objetivo
        rest::Dict{Symbol, ConstraintRef}         # Dicionário de restrições
        fs::Union{Nothing, Dict{Symbol, Float64}} # Solução ótima encontrada
        
        # Construtor principal
        function mp(nome::String="rmp")
            # Cria o modelo JuMP com solver HiGHS
            mdl = Model(HiGHS.Optimizer)
            set_silent(mdl)
            set_optimizer_attribute(mdl, "output_flag", false)  # Disabilitando o relatório do solver
            
            # Inicializa os dicionários vazios
            vars = Dict{Symbol, VariableRef}()
            rest = Dict{Symbol, ConstraintRef}()
            
            # Cria nova instância
            new(modelo, nome, variaveis, nothing, restricoes, nothing)
        end
    end

    
    
    function createRMP(d::Dados.dados) #Rich restricted master problem
        rmp = mp("rmp")
    
        return rmp
    end
    
    
    
    
end
