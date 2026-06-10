#modulo para tratar o subproblema de precificacao (PSP - pricing subproblem)
module Psp
    include("DaTA.jl") #modulo para leitura e impressao de dados
    using .Dados
    include("RmP.jl") #modulo para tratamento do problema mestre restrito (RMP)
    using .Rmp
    
    Base.@kwdef mutable struct qroute
        pred::Tuple{Int, Int} = (0, 0)  # carga q e nó predecessor i
        load::Vector{Int} = Int[]       # carga q[j \in N] Um vetor de 'n' posições para armazenar as cargas carregadas para cada cliente
        cred::Float64 = 0.0             # custo reduzido acumulado da q-route
        bset::BitVector = BitVector()   # conjunto de bits que indica se o cliente j ja foi ou não visitado
        cost::Float64 = 0.0             # custo real da rota
        rseq::Vector{Int} = Int[]       # sequência de visitação da rota
    end


    function qroutes(d::Dados.dados, rmp::Rmp.mp)
        #Pedro Original
        println("q-routes")
        
        # 1. Instanciando os dicionários corretamente com parênteses
        π = Dict{Tuple{Int,Int},Float64}() # armazena o preço dual relativo à visitação
        δ = Dict{Tuple{Int,Int},Float64}() # armazena o preço dual relativo à entrega
        c̄ = Dict{Tuple{Int,Int},Float64}() # armazena custo reduzido da distância
        
        # modificar quando as instancias tiverem frota heterogenea e multiplos produtos
        k = 1
        v = 1

        for t in 1:d.T
            println("t = ", t)
            
            # Pedro: Recupera os duais do problema mestre iterando sobre os clientes no período t
            for i in 1:d.n
                δ[(i, t)] = dual(rmp.cnst[:balanco_cliente][i, t])
                π[(i, t)] = dual(rmp.cnst[:limite_visitas][i, t])
            end
            
            # Correção: O cálculo de c̄ precisa estar dentro do laço t e usar a tupla (i, t)
            for a in d.A
                i = a[1]
                if i > 0 && i < d.n + 1
                    c̄[a] = d.c[a] - π[(i, t)]
                else
                    c̄[a] = d.c[a]
                end
            end
            
            # inicialização (O código original do professor continua a partir daqui com R = ...) #mudei até aqui#
            println("t = ", t)
            
            #inicialização
            #R00 = qroute()  #rotulo fundamental
            R = [qroute() for q in 1:d.Q[v], j in 1:d.n]
            for q in 1:d.Q[v]
                for j in 1:d.n
                    if q ≤ d.Mtil[(j,k,v,t)]
                        qⱼ = int(q)
                        R[(q,j)] = qroute(
                            pred = (0, 0), 
                            load = [i == j ? qⱼ : 0 for i in 1:d.n], 
                            cred = d.c[(i,j)] - qⱼ*δ[(j,t)], 
                            bset = BitVector(i == j for i in 1:d.n),
                            cost = d.c[(i,j)],
                            rseq = [(j)]
                        )
                    else
                        R[(q,j)] = qroute(
                            pred = (-1, -1), 
                            load = zeros(Int, d.n), 
                            cred = +Inf, 
                            bset = falses(d.n),
                            cost = +Inf,
                            rseq = Int[]
                        )
                    end
                end
            end
            
            #preenchimento
            for q₁ in 1:d.Q[v]
                for i in 1:d.n
                    if R[(q₁,i)].cred != +Inf
                        for q₂ in (int(q₁)+1):d.Q[v]
                            for j in 1:d.n
                                Δ = int(q₂) - int(q₁)
                                if R[(q₁,i)].load[j] + Δ ≤ d.Mtil[(j,k,v,t)]
                                    cᵣ = R[(q₁,i)].cred - c̄[(i,j)] - Δ*δ[(j,t)]
                                    if cᵣ < R[(q₂,j)].cred
                                        
                                        # 1. Criar cópias dos vetores da rota do predecessor
                                        novo_load = copy(R[(q₁,i)].load)
                                        novo_load[Int(j)] = novo_load[Int(j)] + Δ
                                        
                                        novo_bset = copy(R[(q₁,i)].bset)
                                        novo_bset[Int(j)] = true
                                        
                                        # 2. Criar a nova qroute e salvar na chave correta (q₂, j)
                                        R[(q₂,j)] = qroute(
                                            pred = (q₁, i), 
                                            load = novo_load, 
                                            cred = cᵣ, 
                                            bset = novo_bset,
                                            cost = R[(q₁,i)].cost + d.c[(i,j)],
                                            rseq = [R[(q₁,i)].rseq; j]
                                        )
                                    end
                                end
                            end
                        end
                    end
                end
            end

            #recuperacao
            for q in 1:d.Q[v]
                for j in 1:d.n
                    cᵣ = R[(q,j)].cred #custo reduzido
                    if cᵣ < 0 #se o custo reduzido cᵣ da q-route é negativo                        
                        # vetor de n zeros do tipo Int64 (padrão se o tipo for omitido)
                        vNumVisitas = zeros(Int64, n)
                        for i in R[(q,j)].rseq
                            vNumVisitas[i] += 1
                        end

                        # Pedro: adicionar a rota como coluna ao PMR
                        Rmp.adicionar_coluna_prp!(rmp, d, t, R[(q,j)].load, vNumVisitas, R[(q,j)].cost)
                    end
                end
            end            
        end
    end
end



                            
                        #=
                        # Ordem de visitação da q-route
                        vRota = Int[]
                        #informação dos predecessores
                        i = R[(q,j)].pred[2]
                        qᵢ = R[(q,j)].pred[1]
                        while (i != 0 && qᵢ != 0)
                            push!(vRota, i)
                            vNumVisitas[i] += 1 
                            
                            #recuperar a rota, cliente i e carga qᵢ da célula antecessora
                            temp₁ = i
                            temp₂ = qᵢ
                            i = R[(temp₂,temp₁)].pred[2]
                            qᵢ = R[(temp₂,temp₁)].pred[1]                            
                        end
                        =#


    #=
    # Opção A: Tudo padrão (vazio/zerado)
    obj1 = qroute()

    # Opção B: Modificando apenas o que você precisa
    obj2 = qroute(cred = 42.0)

    # Opção C: Passando todos os valores de forma clara
    obj3 = qroute(
        pred = (5, 5), 
        load = [10, 20, 30], 
        cred = 1.5, 
        bset = BitVector([1, 0, 1])
    )
    =#