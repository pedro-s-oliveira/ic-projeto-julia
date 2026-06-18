#modulo para tratar o subproblema de precificacao (PSP - pricing subproblem)
module Psp
    include("DaTA.jl") #modulo para leitura e impressao de dados
    using .Dados
    include("RmP.jl") #modulo para tratamento do problema mestre restrito (RMP)
    using .Rmp
    include("PMR.jl") #modulo para tratamento do problema mestre restrito (PMR)
    #using .PMR

    Base.@kwdef mutable struct qroute
        pred::Tuple{Int, Int} = (0, 0)  # carga q e nó predecessor i
        load::Vector{Int} = Int[]       # carga q[j \in N] Um vetor de 'n' posições para armazenar as cargas carregadas para cada cliente
        cred::Float64 = 0.0             # custo reduzido acumulado da q-route
        bset::BitVector = BitVector()   # conjunto de bits que indica se o cliente j ja foi ou não visitado
        cost::Float64 = 0.0             # custo real da rota
        rseq::Vector{Int} = Int[]       # sequência de visitação da rota
    end


    #function qroutes(d::Dados.dados, rmp::Rmp.mp)
    function qroutes(d, rmp)
        println("q-routes")
        #Pedro
        #recupera os duais do problema mestres para cada 
        π = Dict{Tuple{Int,Int},Float64} # armazena o preço dual relativo à visitação do cliente i no período t 
        δ = Dict{Tuple{Int,Int},Float64} # armazena o preço dual relativo à entrega ao cliente i no período t        
        
        #armazena custo reduzido da distância
        c̄ = Dict{Tuple{Int,Int},Float64}
        
        #calculo do custo reduzido da distância
        for a in d.A
            i = a[1]
            for t in 1:d.T
            if i > 0 && i < d.n + 1
                c̄[a] = d.c[a] - π[(i,t)]                
            end
        end
        
        #modificar quando as instancias tiverem frota heterogenea e multiplos produtos
        k = 1
        v = 1

        for t in 1:d.T
            println("t = ", t)

            # Recuperação dinâmica dos duais por cliente e período
            for i in 1:d.n
                δ[(i, t)] = dual(rmp.cnst[:balanco_cliente][i, t])
                π[(i, t)] = dual(rmp.cnst[:limite_visitas][i, t])
            end
            
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
                                        novo_load = copy(R[(q₁,i)].load)
                                        novo_load[Int(j)] = novo_load[Int(j)] + Δ

                                        novo_bset = copy(R[(q₁,i)].bset)
                                        novo_bset[Int(j)] = true
                                        

                                        R[(q₂,j)] = qroute(
                                            pred = (q₁, i), 
                                            load=int(j) = novo_load[int(j)], 
                                            cred = cᵣ, 
                                            bset=int(j) = novo_bset[int(j)],
                                            cost = R[(q₁,i)].cost + d.c[(i,j)],
                                            rseq = [R[(q₁,i)].rseq;j]
                                        )
                                    end
                                end
                            end
                        end
                    end
                end
            end

            println("Tudo certo até aqui, pressione Enter para continuar...")
            readline()
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

                        #Pedro
                        #adicionar a rota como coluna ao PMR
                        #utilizar vNumVisitas (é o z̄ no PMR), R[].load (é o q̄ no PMR) e R[].cost (é o cᵣ da f.o. do PMR)
                        #R[(q,j)].rseq, q (carga total que é igual a soma das cargas no R[].load), R[].load, R[].cost
                        #para armazenar as rotas reais geradas
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

    #=
    function qroutes_prp(d_prp, alpha1, alpha2, alpha3, t, E, UE)
    total_nodes = d_prp.n + 2
    deposito, copia = 1, total_nodes
    cap = d_prp.C 

    # 1. Custos Reduzidos dos Arcos 
    _c = zeros(Float64, total_nodes, total_nodes)
    for i in 1:(total_nodes-1), j in 2:total_nodes
        if i != j
            dist = d_prp.c[i, j]
            _c[i, j] = (j == copia) ? dist : dist - ((alpha2[j, t] - alpha1[t]) * d_prp.d[j, t])
        end
    end

    # 2. Programação Dinâmica COM ELEMENTARIEDADE (Prevenção de Ciclos)
    R = [QRoute() for o in 1:(cap + 1), i in 1:total_nodes]
    for o in 0:cap, i in 2:total_nodes
        idx = o + 1
        dem = (i == copia) ? 0 : d_prp.d[i, t]
        if o == dem
            R[idx, i].rc = (i != copia) ? _c[i, copia] : 0.0
            R[idx, i].j, R[idx, i].d = copia, o - dem
            
            # Inicializa a memória da rota (BitSet)
            R[idx, i].U = BitSet()
            if i != copia
                push!(R[idx, i].U, i)
            end
        elseif o < dem 
            R[idx, i].rc = 1e9 
        end
    end

    for o in 1:cap, i in 2:(total_nodes-1)
        dem = d_prp.d[i, t]
        if o > dem
            best_rc, next_node = 1e9, -1
            best_U = BitSet()
            prev_idx = o - dem + 1
            
            for j in 2:total_nodes
                # MÁGICA AQUI: !(i in R[prev_idx, j].U) bloqueia clientes já visitados!
                if i != j && !(i in R[prev_idx, j].U)
                    if R[prev_idx, j].rc + _c[i, j] < best_rc
                        best_rc = R[prev_idx, j].rc + _c[i, j]
                        next_node = j
                        best_U = R[prev_idx, j].U
                    end
                end
            end
            
            R[o+1, i].rc, R[o+1, i].j, R[o+1, i].d = best_rc, next_node, o - dem
            R[o+1, i].U = copy(best_U)
            push!(R[o+1, i].U, i) # Salva o cliente 'i' como visitado
        end
    end

    # 3. Recuperação da Melhor Rota
    best_total_rc, best_i, best_o = 1e9, -1, -1
    for i in 2:(total_nodes-1), o in d_prp.d[i, t]:cap
        lucro_inicial = (alpha2[i, t] - alpha1[t]) * d_prp.d[i, t]
        custo_arco_inicial = d_prp.c[deposito, i] - lucro_inicial
        
        if custo_arco_inicial + R[o+1, i].rc < best_total_rc
            best_total_rc = custo_arco_inicial + R[o+1, i].rc
            best_i, best_o = i, o
        end
    end

    final_rc = best_total_rc + alpha3[t]
    if final_rc >= -0.001 
        return final_rc, Int[], 0.0 
    end

    # Traceback da rota real
    entregas, custo_real = zeros(Int, total_nodes), d_prp.c[deposito, best_i]
    curr_i, curr_o = best_i, best_o
    entregas[curr_i] = d_prp.d[curr_i, t]
    
    while R[curr_o+1, curr_i].j != copia
        next_j = R[curr_o+1, curr_i].j
        custo_real += d_prp.c[curr_i, next_j]
        curr_o, curr_i = R[curr_o+1, curr_i].d, next_j
        entregas[curr_i] = d_prp.d[curr_i, t]
    end
    
    return final_rc, entregas, custo_real + d_prp.c[curr_i, copia]
end
    
    
    =#