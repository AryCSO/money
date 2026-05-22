# Módulo de Login / Autenticação

> Tela de login na abertura do app, cadastro protegido por token de
> administrador e seed de credenciais padrão em toda geração do banco.

## 1. Comportamento

- Ao abrir o app, a **primeira tela é o login** (a sessão não é persistida —
  exige login a cada execução).
- **Login:** e-mail, senha, botão **"Acessar"** e link **"Não é cadastrado
  ainda? Cadastrar-se"**.
- **Cadastro:** e-mail válido, nome completo, "como prefere ser chamado",
  senha + confirmação e **token de administrador**. O cadastro só é aprovado
  com o token correto (senha que só o desenvolvimento conhece).
- Após login/cadastro bem-sucedido, abre o `MainLayout`. No topo, o avatar vira
  um menu com o nome/e-mail do usuário e a opção **"Sair"** (logout).

## 2. Banco de dados (Firebird)

Tabela nova `USUARIOS` (em `database_service_io.dart`):

| Coluna | Tipo |
|---|---|
| ID | BIGINT identity PK |
| EMAIL | VARCHAR(255) UNIQUE |
| NOME_COMPLETO | VARCHAR(255) |
| NOME_PREFERIDO | VARCHAR(120) |
| SALT | VARCHAR(64) |
| SENHA_HASH | VARCHAR(128) |
| CRIADO_EM | TIMESTAMP |

O token de administrador fica em `APP_META` (chave `admin_token`).

### Seed em toda geração do banco (`_seedDefaultAuth`)

Executado em `_ensureSchema` (toda abertura). Insere se ausente, **sem
sobrescrever** valores já existentes:

- Usuário padrão: **`arycarvalho1969@gmail.com`** / senha **`101812Ar@`**
  (nome "Ary Carvalho", apelido "Ary").
- Token de administrador padrão: **`101812`**.

> Os valores padrão são constantes em `DatabaseService` (`_defaultUserEmail`,
> `_defaultUserPassword`, `_defaultAdminToken`, etc.). Para alterá-los no
> produto, mude essas constantes — o seed não regrava se o registro já existe.

### Segurança da senha

Senha nunca é armazenada em texto puro. Hash = `sha256(salt + ':' + senha)`,
com `salt` aleatório de 16 bytes por usuário (`Random.secure`). Verificação em
`autenticarUsuario` recomputa o hash com o salt salvo. (Pacote `crypto`.)

### Métodos (io + stub web)

- `autenticarUsuario({email, senha})` → mapa do usuário (sem hash) ou `null`.
- `emailJaCadastrado(email)` → bool.
- `validarTokenAdmin(token)` → compara com `APP_META.admin_token`.
- `registrarUsuario({email, senha, nomeCompleto, nomePreferido})` → ID
  (lança `StateError` se o e-mail já existe).

No web (sem Firebird) os métodos retornam valores neutros — login não funciona
na web, coerente com o app ser desktop.

## 3. Camada de apresentação

| Arquivo | Papel |
|---|---|
| `lib/presentation/viewmodels/auth_viewmodel.dart` | `AuthViewModel` (estado de sessão) + `AuthUser`. `login`, `register` (valida e-mail/senha/confirmação/token), `logout`. |
| `lib/presentation/views/login_page.dart` | Tela única alternando login ↔ cadastro. |
| `lib/app.dart` | `home` usa `Consumer<AuthViewModel>`: `LoginPage` se não autenticado, `MainLayout` caso contrário. |
| `lib/presentation/views/main_layout.dart` | `_UserMenu` no topo (nome/e-mail + "Sair"). |
| `lib/main.dart` | Registra `AuthViewModel` no `MultiProvider`. |

### Validações no cadastro (`AuthViewModel.register`)

E-mail com regex básica, nome completo e apelido obrigatórios, senha ≥ 6
caracteres, confirmação igual, token de administrador válido. Mensagens de erro
exibidas na própria tela.

## 4. Pontos de atenção

- **Sessão não persistida:** decisão de produto ("a tela inicial será login").
  Para manter logado entre execuções, persistir o ID do usuário em
  SharedPreferences e restaurar no `AuthViewModel`.
- **Token de admin é segredo de cadastro**, não de login. Qualquer um com o
  token pode criar conta — convém trocá-lo do padrão `101812` em produção
  (alterando a constante e/ou o valor em `APP_META`).
- **Dependência:** `crypto` adicionada ao `pubspec.yaml`.
- **Não testável offline:** o login real exige o Firebird; verificação feita por
  análise estática + testes de unidade existentes.
