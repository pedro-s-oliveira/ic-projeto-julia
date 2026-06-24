# modulo para tratar o subproblema de precificacao (PSP - pricing subproblem)
module Psp
    include("DaTA.jl") 
    using .Dados
    include("RmP.jl") 
    using .Rmp
    include("PMR.jl") 

    Base.@kwdef mutable struct qroute
        pred::Tuple{Int, Int} = (0, 0)
        load::Vector{Int} = Int[]
        cred::Float64 = 0.0
        bset::BitVector = BitVector()
        cost::Float64 = 0.0
        rseq::Vector{Int} = Int[]
    end

    function qroutes(d, rmp)
        println("q-routes")
        
        π = Dict{Tuple{Int,Int},Float64}() 
        δ = Dict{Tuple{Int,Int},Float64}() 
        c̄ = Dict{Tuple{Int,Int},Float64}()
        
        # 1. NOVOS DUAIS: Extraindo as taxas da fábrica e limite de frota
        α1 = Dict{Int,Float64}() 
        π0 = Dict{Int,Float64}() 
        
        for t_all in 1:d.T
            α1[t_all] = dual(rmp.cnst[:balanco_planta][t_all])
            π0[t_all] = dual(rmp.cnst[:limite_veiculos][t_all])
            
            for i_all in 1:d.n
                δ[(i_all, t_all)] = dual(rmp.cnst[:balanco_cliente][i_all, t_all])
                π[(i_all, t_all)] = dual(rmp.cnst[:limite_visitas][i_all, t_all])
            end
        end
        
        k = 1
        v = 1

        for t in 1:d.T
            for a in d.A
                i = a[1]
                if i > 0 && i < d.n + 1
                    c̄[a] = d.c[a] - π[(i,t)]
                else
                    c̄[a] = d.c[a]
                end
            end
            
            # Inicialização
            R = [qroute() for q in 1:d.Q[v], j in 1:d.n]
            for q in 1:d.Q[v]
                for j in 1:d.n
                    if q <= d.Mtil[(j,k,v,t)]
                        qⱼ = Int(q)
                        
                        # 2. INCLUINDO AS TAXAS: Custo da frota (-π0) e Custo real do produto na fábrica (-α1)
                        credito_inicial = d.c[(0,j)] - π0[t] - qⱼ * (δ[(j,t)] - α1[t])
                        
                        R[q, j] = qroute(
                            pred = (0, 0), 
                            load = [cliente == j ? qⱼ : 0 for cliente in 1:d.n], 
                            cred = credito_inicial, 
                            bset = BitVector(cliente == j for cliente in 1:d.n),
                            cost = d.c[(0,j)],
                            rseq = [j]
                        )
                    else
                        R[q, j] = qroute(
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
            
            # Preenchimento
            for q₁ in 1:d.Q[v]
                for i in 1:d.n
                    if R[q₁, i].cred != +Inf
                        for q₂ in (Int(q₁)+1):d.Q[v]
                            for j in 1:d.n
                                
                                if i != j && !R[q₁, i].bset[Int(j)]
                                    
                                    Δ = Int(q₂) - Int(q₁)
                                    if R[q₁, i].load[j] + Δ <= d.Mtil[(j,k,v,t)]
                                        
                                        # 3. O ERRO FATAL: Custo da distância (c̄) sendo SOMADO (+), não subtraído!
                                        cᵣ = R[q₁, i].cred + c̄[(i,j)] - Δ * (δ[(j,t)] - α1[t])
                                        
                                        if cᵣ < R[q₂, j].cred
                                            
                                            novo_load = copy(R[q₁, i].load)
                                            novo_load[Int(j)] = novo_load[Int(j)] + Δ

                                            novo_bset = copy(R[q₁, i].bset)
                                            novo_bset[Int(j)] = true

                                            R[q₂, j] = qroute(
                                                pred = (q₁, i), 
                                                load = novo_load, 
                                                cred = cᵣ, 
                                                bset = novo_bset,
                                                cost = R[q₁, i].cost + d.c[(i,j)],
                                                rseq = [R[q₁, i].rseq; j]
                                            )
                                        end
                                    end
                                end
                                
                            end
                        end
                    end
                end
            end
            
            # Recuperacao e injeção
            rotas_adicionadas = 0
            for j in 1:d.n
                melhor_q = -1
                melhor_cr = 0.0

                for q in 1:d.Q[v]
                    if R[q, j].cred < melhor_cr
                        melhor_cr = R[q, j].cred
                        melhor_q = q
                    end
                end

                if melhor_cr < -1e-4
                    vNumVisitas = zeros(Int64, d.n)
                    for i in R[melhor_q, j].rseq
                        vNumVisitas[i] += 1
                    end

                    adicionar_coluna_prp!(rmp, d, t, R[melhor_q, j].load, vNumVisitas, R[melhor_q, j].cost)
                    rotas_adicionadas += 1
                end
            end
            println("   -> ", rotas_adicionadas, " rotas diversificadas injetadas neste dia.")
        end
    end
end