#modulo para tratar a componente do roteamento (Vehicle-routing problem/VRP)
module Vrp    
    
    mutable struct rt #rota/route
        vOrder::Vector{Int}     #ordem/sequencia de visitacao
        fCost::Float64          #custo da rota
        iLoad::Int              #carga transportada
        iFirst::Int             #primeiro
        iLast::Int              #ultimo
        iTTT::Int               #tempo total de viagem (total travel time)
    end
    
    mutable struct vrs #solução do roteamento
        vRot::Vector{rt}  #vetor com as rotas
        fCst::Float64     #custo da solução
        vCpp::Vector{Int} #Clientes por partição
        vPS::Dict{Tuple{Int,Int},Int}
        
    end

end
