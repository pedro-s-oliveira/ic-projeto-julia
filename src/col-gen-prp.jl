using JuMP
using HiGHS

#modulo para leitura e impressao de dados
include("DaTA.jl") 
using .Dados

#modulo para tratamento do problema mestre restrito (RMP - restricted master problem)
include("RmP.jl") 
using .Rmp

#modulo para tratamendo do subproblema de precificação (PSP - pricing subproblem)
include("PsP.jl") 
using .Psp

#modulo para tratamendo das informações de roteamento
include("VrP.jl") 
using .Vrp




function main()
    #inicializa o objeto dados d e o preenche com a leitura do arquivo externo
    d = Dados.dados()
    Dados.leitura(d)
    
    
    print("\nok\n")
    return 0
    exit()

end

output = main()
println(output)
