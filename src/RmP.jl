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
        cnst::Dict{Symbol, ConstraintRef}         # Dicionário de restrições
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

    # Métodos para adicionar componentes ao modelo
    function adicionar_variavel!(m::mp, nome::Symbol, lb::Real=0.0, 
                                ub::Real=Inf, tipo::Symbol=:continua)
        # Tipos suportados
        tipo_map = Dict(
            :continua => (lb, ub),
            :inteira => Int,
            :binaria => Bin
        )
        
        if !(tipo in keys(tipo_map))
            error("Tipo de variável não suportado. Use :continua, :inteira ou :binaria")
            exit()
        end
        
        # Cria variável conforme o tipo
        if tipo == :continua
            lim_inf, lim_sup = tipo_map[tipo]
            var_ref = @variable(m.mdl, lim_inf <= nome <= lim_sup)
        elseif tipo == :inteira
            var_ref = @variable(m.mdl, integer=true, lower_bound=lb, 
                            upper_bound=ub, base_name=String(nome))
        else  # :binaria
            var_ref = @variable(m.mdl, binary=true, base_name=String(nome))
        end
        
        # Armazena no dicionário
        m.vars[nome] = var_ref
        println("Variável $nome adicionada (tipo: $tipo)")
        return var_ref
    end

    function definir_objetivo!(m::mp, expressao, sentido::Symbol=:min)
        # Sentido da otimização
        if sentido == :min
            @objective(m.mdl, Min, expressao)
        elseif sentido == :max
            @objective(m.mdl, Max, expressao)
        else
            error("Sentido deve ser :min ou :max")
            exit()
        end
        
        m.obj = expressao
        println("Função objetivo definida (sentido: $sentido)")
    end

    function adicionar_restricao!(m::mp, nome::Symbol, expressao)
        # Cria restrição
        #constr_ref = add_constraint(m.mdl, expressao)
        constr_ref = add_constraint(m.mdl, expressao)
        
        # Armazena no dicionário
        m.cnst[nome] = constr_ref
        println("Restrição $nome adicionada")
        return constr_ref
    end

    # Métodos para resolver e acessar resultados
    function resolver!(m::mp)
        println("Resolvendo modelo $(m.nome)...")
        
        # Otimiza o modelo
        optimize!(m.mdl)
        
        # Verifica status
        status = termination_status(m.mdl)
        println("Status: $status")
        
        if status == MOI.OPTIMAL
            # Armazena a solução ótima
            m.fs = Dict{Symbol, Float64}()
            for (nome, var) in m.variaveis
                m.fs[nome] = value(var)
            end
            
            println("Solução ótima encontrada!")
            println("Valor da função objetivo: ", objective_value(m.mdl))
        else
            println("Solução ótima não encontrada.")
            m.fs = nothing
        end
        
        return status
    end

    function obter_solucao(m::mp)
        if m.fs === nothing
            println("Modelo não resolvido ou sem solução ótima.")
            return nothing
        end
        
        return m.fs
    end

    function relatorio(m::mp)
        println("\n" * "="^50)
        println("RELATÓRIO DO MODELO: $(m.nome)")
        println("="^50)
        
        # Informações gerais
        println("\nVARIÁVEIS ($(length(m.variaveis))):")
        for (nome, var) in m.variaveis
            lb = has_lower_bound(var) ? lower_bound(var) : "-∞"
            ub = has_upper_bound(var) ? upper_bound(var) : "∞"
            tipo = is_binary(var) ? "Binária" : (is_integer(var) ? "Inteira" : "Contínua")
            
            print("  $nome: $tipo, Domínio: [$lb, $ub]")
            
            if m.fs !== nothing
                valor = m.fs[nome]
                print(", Valor: ", round(valor, digits=4))
            end
            println()
        end
        
        println("\nRESTRIÇÕES ($(length(m.cnst))):")
        for (nome, constr) in m.cnst
            println("  $nome: $(constraint_object(constr).func) $(constraint_object(constr).set)")
        end
        
        if m.fs !== nothing
            println("\nSOLUÇÃO ÓTIMA:")
            println("  Valor FO: ", objective_value(m.mdl))
            println("  Gap: ", round((objective_bound(m.mdl) - objective_value(m.mdl)) / 
                objective_bound(m.mdl) * 100, digits=2), "%")
        end
        
        println("="^50)
    end
    
    function createRMP(d::Dados.dados) #Rich restricted master problem
        #Criando Problema Mestre Restrito (PMR) 
        # Exemplo: cria um problema de transporte
        println("Criando PMR...")

        #rmp é um struct do tipo mp
        rmp = mp("rmp")
        #parei aqui
    
        return rmp
    end
    
    
    
    
end
