# Projeto de Otimização - Engenharia de Produção (UFSJ)

Este repositório contém o código para o projeto de Iniciação Científica focado em Pesquisa Operacional e modelos de otimização (como o **PRP2**). O objetivo é desenvolver uma solução modular em Julia para facilitar a manutenção e o trabalho em equipe.

## 📂 Estrutura do Projeto

* `src/`: Contém todo o código-fonte do projeto.
    * `main.jl`: Ponto de entrada que coordena a execução.
    * `calculos.jl`: Módulo responsável pelas funções matemáticas e lógica.
* `test/`: Pasta para scripts de teste e validação.
* `Project.toml` & `Manifest.toml`: Arquivos de configuração do ambiente Julia.

## 🛠️ Como Configurar o Ambiente

Ao baixar este projeto pela primeira vez, siga estes passos para garantir que as bibliotecas funcionem corretamente:

1. Abra o terminal na pasta do projeto.
2. Digite `julia` para abrir o REPL.
3. Entre no modo de pacotes digitando `]`.
4. Ative o ambiente: `activate .`
5. Instale as dependências: `instantiate`

Isso garantirá que você use exatamente as mesmas versões das bibliotecas que eu usei.

## 🤝 Fluxo de Trabalho (Git)

Para mantermos o código organizado, vamos seguir este fluxo:

1. **Sempre comece dando um `Pull`** (Sincronizar) para baixar as atualizações do colega.
2. Faça suas alterações nos módulos específicos (`src/`).
3. **Commit**: Salve suas alterações com uma mensagem clara do que foi feito.
4. **Push**: Envie para o GitHub.

---
**Responsável:** Pedro Santos  
**Universidade:** Federal de São João del-Rei (UFSJ)
