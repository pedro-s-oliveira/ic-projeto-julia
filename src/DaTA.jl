#modulo para tratar os dados do problema
module Dados

    mutable struct dados
        n::Int                              # numero de clientes
        P::Int                              # numero de produtos
        T::Int                              # numero de periodos
        V::Int                              # numero de veiculos
        H::Int                              # limite de tempo de rota
        Q::Dict{Int,Int}                    # Capacidade dos veículos
        e::Dict{Int,Float64}                # custo de utilizacao dos veículos
        x::Dict{Int,Float64}                # Coordenada x
        y::Dict{Int,Float64}                # Coordenada y
        c::Dict{Tuple{Int,Int},Float64}     # Custo de conexão
        I0::Dict{Tuple{Int,Int},Int}        # Estoque inicial
        h::Dict{Tuple{Int,Int},Float64}     # Custo de inventário
        U::Dict{Tuple{Int,Int},Int}         # Limite de estoque
        C::Dict{Int,Int}                    # Capacidade de produção
        l::Dict{Int,Float64}                # Custo fixo/setup de produção
        u::Dict{Int,Float64}                # Custo unitário/variável de produção
        s::Dict{Int,Float64}                # Tempo de servico
        B::Dict{Tuple{Int,Int},Float64}     # Penalidade de atraso
        d::Dict{Tuple{Int,Int,Int},Int}     # Demanda
        A::Set{Tuple{Int,Int}}              # Conjunto de conexoes
        Mbar::Dict{Tuple{Int,Int},Float64}
        Mtil::Dict{Tuple{Int,Int,Int,Int},Float64}


        # Construtor sem argumentos (default) do struct data
        function dados()
            return new(0,0,0,0,0, Dict{Int,Int}(), Dict{Int,Float64}(),
                                Dict{Int,Float64}(), Dict{Int,Float64}(),                    
                                Dict{Tuple{Int,Int},Float64}(), Dict{Tuple{Int,Int},Int}(),
                                Dict{Tuple{Int,Int},Float64}(), Dict{Tuple{Int,Int},Int}(),
                                Dict{Int,Int}(), Dict{Int,Float64}(),
                                Dict{Int,Float64}(), Dict{Tuple{Int,Int},Float64}(),
                                Dict{Tuple{Int,Int},Float64}(), Dict{Tuple{Int,Int,Int},Int}(),
                                Set{Tuple{Int,Int}}(), 
                                Dict{Tuple{Int,Int},Float64}(),
                                Dict{Tuple{Int,Int,Int,Int},Float64}())
        end

    end
    
    
    #leitura dos dados
    # leitura dos dados
    function leitura(d::dados, caminho::String)
        
        arquivo = open(caminho, "r") do file
            read(file, String)
        end

        # Leia todas as linhas do arquivo
        linhas = readlines(caminho)    
        
        # indica qual linha ler do arquivo de dados
        linha = 1
        # ... (AQUI CONTINUA O RESTO DO SEU CÓDIGO IGUALZINHO ESTAVA ANTES) ...
        d.n = parse(Int, linhas[linha])
        #println("\nn = ",d.n)
        N = 0:d.n                 #conjunto de nós
        N_ = 1:d.n                #conjunto de nós clientes/revendedores
        #println("N_ = ",N_)
        #println("N = ",N)

        linha += 1
        d.T = parse(Int, linhas[linha])     
        #println("\nT = ",d.T)
        
        linha += 1
        d.P = parse(Int, linhas[linha])     
        #println("\nP = ",d.P)

        linha += 1
        d.V = parse(Int, linhas[linha])     
        #println("\nV = ",d.V)    

        linha += 1
        d.H = parse(Int, linhas[linha])    
        #println("\nH = ",d.H)

        linha += 1
        #informacoes sobre os veiculos
        #d.Q = Dict{Int, Int}()        #capacidade dos veiculos
        #d.e = Dict{Int,Float64}()     #custo de utilizacao de cada veiculo
        for v in 1:d.V
            temp = Dict{Int, Float64}()
            temp = parse.(Int, split(linhas[linha]))
            d.Q[v] = temp[1]
            d.e[v] = temp[2]
            #println("v = ", v, " -> Q = ", d.Q[v], " -> e = ", d.e[v])
            linha += 1
        end

        #lendo informacoes dos nós clientes e plantas
        for i in N
            #criando um vetor com todas as informações da linha
            temp = Dict{Int, Float64}()
            temp = parse.(Float64, split(linhas[linha]))
            #repassando as informações
            d.x[i] = temp[1]
            d.y[i] = temp[2]
            #print("\ni=",i,"->x=",d.x[i],"|y=",d.y[i],"->")
            if i == 0
                #lendo informações da planta produtiva
                for k in 1:d.P
                    d.I0[(i,k)] = temp[3]
                    d.h[(i,k)] = float.(temp[4])
                    d.U[(i,k)] = temp[5]
                    d.C[k] = temp[6]
                    d.l[k] = temp[7]
                    d.u[k] = temp[8]
                    #print("k=",k,"=>I0=",d.I0[(i,k)],"|h=",d.h[(i,k)],"|U=",d.U[(i,k)],"|C=",d.C[k],"|l=",d.l[k],"|u=",d.u[k],"\n")
                end
                d.x[d.n+1] = d.x[0]
                d.y[d.n+1] = d.y[0]
            elseif i > 0
                d.s[i] = temp[3]
                for k in 1:d.P
                    d.I0[(i,k)] = temp[4]
                    d.h[(i,k)] = temp[5]
                    d.U[(i,k)] = temp[6]
                    d.B[(i,k)] = temp[7]
                    #print("k=",k,"=>I0=",d.I0[(i,k)],"|h=",d.h[(i,k)],"|U=",d.U[(i,k)],"|B=",d.B[(i,k)],"\n")
                end
            end

            linha += 1
        end

        #demandas de cada cliente por cada produto em cada periodo
        #d.d = Dict{Tuple{Int,Int,Int},Int}()
        for k in 1:d.P
            for i in N_
                temp = Dict{Int, Float64}()
                temp = parse.(Int, split(linhas[linha]))
                for t in 1:d.T d.d[(i,k,t)] = temp[t] end
                linha += 1
            end
        end

        #println(d)
        #set 𝒜 := {i in N_, j in N_: i != j} union {i in N, j in N_: i = 0} union {i in N_, j in N: j = 0};      #conjuntos de arestas
        #d.A = Set{Tuple{Int,Int}}() #arestas que existem no grafo
        for i in N 
            for j in 1:d.n+1  
                if i == 0 && j > 0 && j < d.n+1
                    push!(d.A,(i,j)) 
                elseif i > 0 && i < d.n+1 && j == 0
                    push!(d.A,(j,i)) 
                elseif i > 0 && i < d.n+1 && j > 0 && j < d.n+1 && i != j
                    push!(d.A,(i,j))
                end
            end        
        end

        #print("\n\nA=",d.A)

        # custos de roteamento c_ij
        #c = Dict()
        #d.c = Dict{Tuple{Int,Int},Float64}()
        for a in d.A
            i = a[1]
            j = a[2]
            d.c[a] = sqrt((abs(d.x[i] - d.x[j]))^2 + (abs(d.y[i] - d.y[j]))^2)    
        end
        #print("\n\nc=",d.c)

        #Mbar = Dict{Tuple{Int,Int},Float64}()
        for t in 1:d.T
            for k in 1:d.P
                local dMaxK = 0
                for e in t:d.T
                    for i in N_ dMaxK += d.d[(i,k,e)] end
                end
                d.Mbar[(k,t)] = min(d.C[k],dMaxK)
            end
        end

        #print("\nMbar = ", d.Mbar)

        #Mtil = Dict{Tuple{Int,Int,Int,Int},Float64}()
        for t in 1:d.T
            for v in 1:d.V
                for k in 1:d.P            
                    for i in N_
                        local rDem = 0  #demanda residual                
                        for e in t:d.T rDem += d.d[(i,k,e)] end
                        M = min(d.U[(i,k)],d.Q[v])
                        d.Mtil[(i,k,v,t)] = min(M,rDem)
                    end            
                end
            end
        end

        #print("\nMtil = ", d.Mtil)

        #print("\nLeitura de dados ok!")
    end
end
