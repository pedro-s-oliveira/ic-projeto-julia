#modulo para tratar o subproblema de precificacao (PSP - pricing subproblem)
module Psp
    include("DaTA.jl") #modulo para leitura e impressao de dados
    using .Dados
    include("RmP.jl") #modulo para tratamento do problema mestre restrito (RMP)
    using .Rmp
    
    
    mutable struct qroute
        iCurr::Int      #no atual (i)
        jPred::Int      #no sequencial (j)
        dLoad::Int      #carga transportada (d)
        rCost::Float64  #custo reduzido (reduced cost)
        bU::BitVector   #utilizado pelos cortes SDC
        bE::BitVector   #utilizado pela técnica de aceleração DSSR
        
        # Construtor sem argumentos (default) do struct data
        function qroute()
            return new(0,0,0,0.0,0,falses(0),falses(0))
        end
    end

    function qroutes(d::Dados.dados, rmp::Rmp.mp)
        println("q-routes")
        #recupera os duais do problema mestres
        pi_ = Dict{Int,Float64}
        
        #armazena custo reduzido da distância
        c_ = Dict{Tuple{Int,Int},Float64}
        
        #calculo do custo reduzido da distância
        for a in d.A
            i = a[1]
            if i > 0 && i < d.n + 1
                c_[a] = d.c[a] - pi_[i]
            end
        end        
    end


end
