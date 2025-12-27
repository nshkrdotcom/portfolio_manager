# 08. Security & Observability Architecture

## Expert Panel: Security Architect & SRE Perspectives

This document provides comprehensive security architecture and observability patterns for the RAG ecosystem, addressing enterprise-grade requirements for multi-tenant deployments, regulatory compliance, and operational excellence.

---

## 1. Security Boundaries & Threat Model

### 1.1 Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL ZONE                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Users     │  │  API Keys   │  │  Webhooks   │  │ Git Remotes │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
└─────────┼────────────────┼────────────────┼────────────────┼────────────────┘
          │                │                │                │
          ▼                ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DMZ / EDGE ZONE                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                        API Gateway / Load Balancer                    │  │
│  │  • Rate Limiting  • WAF Rules  • TLS Termination  • Request Signing  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           APPLICATION ZONE                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  Auth Service   │  │   API Service   │  │  Query Engine   │             │
│  │  (JWT/OIDC)     │  │  (GraphQL/REST) │  │  (RAG Pipeline) │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           │                    │                    │                       │
│           ▼                    ▼                    ▼                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                      Authorization Layer (RBAC/ABAC)                  │  │
│  │  • Resource Policies  • Tenant Isolation  • Capability Checks        │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DATA ZONE                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │   Postgres   │  │    Neo4j    │  │   Vector DB   │  │  Doc Store   │    │
│  │ (encrypted)  │  │ (encrypted)  │  │ (encrypted)   │  │ (encrypted)  │    │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            EXTERNAL SERVICES                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                      │
│  │  OpenAI API  │  │ Anthropic API│  │  Cloud LLMs  │                      │
│  │  (API Keys)  │  │  (API Keys)  │  │  (OAuth)     │                      │
│  └──────────────┘  └──────────────┘  └──────────────┘                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Threat Model (STRIDE Analysis)

```elixir
defmodule PortfolioCore.Security.ThreatModel do
  @moduledoc """
  STRIDE threat categories and mitigations for the RAG ecosystem.
  """

  @threats %{
    spoofing: %{
      description: "Attacker impersonates legitimate user/service",
      vectors: [
        "Stolen API keys",
        "JWT token theft",
        "Service impersonation"
      ],
      mitigations: [
        "Short-lived tokens (15m access, 7d refresh)",
        "Mutual TLS for service-to-service",
        "API key rotation with overlapping validity",
        "Device fingerprinting"
      ]
    },
    tampering: %{
      description: "Unauthorized modification of data",
      vectors: [
        "SQL injection",
        "Graph query injection (Cypher)",
        "Document manipulation",
        "Embedding poisoning"
      ],
      mitigations: [
        "Parameterized queries only",
        "Input validation at port boundaries",
        "Content signing for documents",
        "Embedding integrity checks"
      ]
    },
    repudiation: %{
      description: "User denies performing action",
      vectors: [
        "Missing audit logs",
        "Log tampering",
        "Incomplete transaction records"
      ],
      mitigations: [
        "Append-only audit log (immutable)",
        "Cryptographic signing of events",
        "Distributed logging with replication"
      ]
    },
    information_disclosure: %{
      description: "Unauthorized data access",
      vectors: [
        "RAG prompt injection",
        "Cross-tenant data leakage",
        "Verbose error messages",
        "Embedding inversion attacks"
      ],
      mitigations: [
        "Tenant isolation at query level",
        "Sanitized error responses",
        "Differential privacy for embeddings",
        "Content filtering in RAG responses"
      ]
    },
    denial_of_service: %{
      description: "System unavailability",
      vectors: [
        "Unbounded queries",
        "Embedding computation exhaustion",
        "Connection pool exhaustion"
      ],
      mitigations: [
        "Query complexity limits",
        "Rate limiting per tenant",
        "Circuit breakers",
        "Resource quotas"
      ]
    },
    elevation_of_privilege: %{
      description: "Unauthorized capability access",
      vectors: [
        "Role bypass",
        "Graph traversal to restricted nodes",
        "Pipeline manipulation"
      ],
      mitigations: [
        "Capability-based authorization",
        "Row-level security in databases",
        "Signed pipeline definitions"
      ]
    }
  }

  def analyze_threat(category), do: Map.get(@threats, category)
  def all_threats, do: @threats
end
```

---

## 2. Authentication Architecture

### 2.1 Multi-Provider Authentication

```elixir
defmodule PortfolioCore.Auth.Port do
  @moduledoc """
  Authentication port - abstracts identity providers.
  """

  @type token :: String.t()
  @type claims :: map()
  @type credentials :: map()
  @type provider :: :jwt | :oidc | :api_key | :mtls

  @callback authenticate(credentials()) ::
    {:ok, claims()} | {:error, :invalid_credentials | :expired | :revoked}

  @callback validate_token(token()) ::
    {:ok, claims()} | {:error, :invalid | :expired}

  @callback refresh_token(token()) ::
    {:ok, token(), claims()} | {:error, :refresh_denied}

  @callback revoke_token(token()) :: :ok | {:error, term()}

  @callback introspect(token()) ::
    {:ok, %{active: boolean(), claims: claims()}} | {:error, term()}
end

defmodule PortfolioCore.Auth.JWT.Adapter do
  @behaviour PortfolioCore.Auth.Port

  alias PortfolioCore.Auth.{TokenStore, KeyRotation}

  @impl true
  def authenticate(%{email: email, password: password}) do
    with {:ok, user} <- verify_credentials(email, password),
         {:ok, claims} <- build_claims(user),
         {:ok, token} <- sign_token(claims) do
      {:ok, %{token: token, claims: claims, expires_in: token_ttl()}}
    end
  end

  @impl true
  def validate_token(token) do
    with {:ok, claims} <- verify_signature(token),
         :ok <- check_expiration(claims),
         :ok <- check_not_revoked(claims["jti"]) do
      {:ok, claims}
    end
  end

  defp verify_signature(token) do
    # Use current and previous key for rotation tolerance
    keys = KeyRotation.current_keys()

    Enum.find_value(keys, {:error, :invalid}, fn key ->
      case Joken.verify(token, Joken.Signer.create("RS256", %{"pem" => key})) do
        {:ok, claims} -> {:ok, claims}
        _ -> nil
      end
    end)
  end

  defp check_not_revoked(jti) do
    case TokenStore.revoked?(jti) do
      true -> {:error, :revoked}
      false -> :ok
    end
  end

  defp token_ttl, do: Application.get_env(:portfolio_core, :token_ttl, 900)
end

defmodule PortfolioCore.Auth.OIDC.Adapter do
  @behaviour PortfolioCore.Auth.Port

  @impl true
  def authenticate(%{code: code, redirect_uri: uri, provider: provider}) do
    config = oidc_config(provider)

    with {:ok, tokens} <- exchange_code(code, uri, config),
         {:ok, claims} <- validate_id_token(tokens["id_token"], config),
         {:ok, user} <- upsert_user(claims, provider) do
      {:ok, build_session(user, claims)}
    end
  end

  defp oidc_config(:google), do: %{
    issuer: "https://accounts.google.com",
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
    jwks_uri: "https://www.googleapis.com/oauth2/v3/certs"
  }

  defp oidc_config(:github), do: %{
    issuer: "https://github.com",
    client_id: System.get_env("GITHUB_CLIENT_ID"),
    client_secret: System.get_env("GITHUB_CLIENT_SECRET"),
    # GitHub uses different flow
    token_endpoint: "https://github.com/login/oauth/access_token"
  }
end

defmodule PortfolioCore.Auth.APIKey.Adapter do
  @behaviour PortfolioCore.Auth.Port

  @impl true
  def authenticate(%{api_key: key}) do
    # Keys are stored hashed, with prefix for identification
    # Format: pm_live_xxxx or pm_test_xxxx
    with {:ok, prefix, hash_input} <- parse_key(key),
         {:ok, key_record} <- lookup_by_prefix_and_hash(prefix, hash_input),
         :ok <- check_key_active(key_record),
         :ok <- check_rate_limit(key_record) do
      update_last_used(key_record)
      {:ok, build_claims_from_key(key_record)}
    end
  end

  defp parse_key(<<"pm_", env::binary-size(4), "_", rest::binary>>) do
    {:ok, "pm_#{env}_", rest}
  end
  defp parse_key(_), do: {:error, :invalid_format}

  defp lookup_by_prefix_and_hash(prefix, input) do
    hash = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)

    case Repo.get_by(APIKey, prefix: prefix, key_hash: hash) do
      nil -> {:error, :not_found}
      key -> {:ok, key}
    end
  end
end
```

### 2.2 Key Rotation System

```elixir
defmodule PortfolioCore.Auth.KeyRotation do
  @moduledoc """
  Automatic RSA key rotation for JWT signing.
  Keys overlap for 24 hours during rotation.
  """

  use GenServer
  require Logger

  @rotation_interval_hours 168  # 7 days
  @overlap_hours 24

  defstruct [:current_key, :previous_key, :next_rotation]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def current_keys do
    GenServer.call(__MODULE__, :get_keys)
  end

  def signing_key do
    GenServer.call(__MODULE__, :get_signing_key)
  end

  @impl true
  def init(_opts) do
    state = load_or_generate_keys()
    schedule_rotation(state.next_rotation)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_keys, _from, state) do
    keys = [state.current_key.public | maybe_previous(state)]
    {:reply, keys, state}
  end

  @impl true
  def handle_call(:get_signing_key, _from, state) do
    {:reply, state.current_key.private, state}
  end

  @impl true
  def handle_info(:rotate, state) do
    Logger.info("Rotating JWT signing keys")

    new_state = %{
      current_key: generate_key_pair(),
      previous_key: state.current_key,
      next_rotation: DateTime.add(DateTime.utc_now(), @rotation_interval_hours, :hour)
    }

    persist_keys(new_state)
    schedule_rotation(new_state.next_rotation)

    # Emit telemetry
    :telemetry.execute(
      [:portfolio, :auth, :key_rotation],
      %{count: 1},
      %{next_rotation: new_state.next_rotation}
    )

    {:noreply, new_state}
  end

  defp generate_key_pair do
    {:ok, private_key} = ExPublicKey.generate_key(:rsa, 4096)
    {:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)

    %{
      private: ExPublicKey.pem_encode(private_key),
      public: ExPublicKey.pem_encode(public_key),
      kid: generate_kid(),
      created_at: DateTime.utc_now()
    }
  end

  defp generate_kid do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
```

---

## 3. Authorization Architecture

### 3.1 Capability-Based Authorization

```elixir
defmodule PortfolioCore.Authz.Port do
  @moduledoc """
  Authorization port - capability and policy evaluation.
  """

  @type subject :: map()  # User/service making request
  @type action :: atom()
  @type resource :: map()
  @type context :: map()

  @callback authorize(subject(), action(), resource(), context()) ::
    :allow | {:deny, reason :: atom()}

  @callback list_permissions(subject()) :: [%{resource: term(), actions: [atom()]}]

  @callback check_capability(subject(), capability :: atom()) :: boolean()
end

defmodule PortfolioCore.Authz.ABAC.Adapter do
  @behaviour PortfolioCore.Authz.Port

  alias PortfolioCore.Authz.{PolicyEngine, ResourceResolver}

  @impl true
  def authorize(subject, action, resource, context) do
    attrs = build_attributes(subject, action, resource, context)

    case PolicyEngine.evaluate(attrs) do
      {:permit, _} ->
        audit_decision(:allow, attrs)
        :allow

      {:deny, reason} ->
        audit_decision(:deny, attrs, reason)
        {:deny, reason}

      {:not_applicable, _} ->
        # Default deny
        audit_decision(:deny, attrs, :no_matching_policy)
        {:deny, :no_matching_policy}
    end
  end

  defp build_attributes(subject, action, resource, context) do
    %{
      subject: %{
        id: subject.id,
        roles: subject.roles,
        tenant_id: subject.tenant_id,
        capabilities: subject.capabilities || [],
        attributes: subject.attributes || %{}
      },
      action: action,
      resource: %{
        type: resource_type(resource),
        id: resource.id,
        owner_id: resource[:owner_id],
        tenant_id: resource[:tenant_id],
        attributes: resource[:attributes] || %{}
      },
      environment: %{
        time: DateTime.utc_now(),
        ip_address: context[:ip_address],
        request_id: context[:request_id]
      }
    }
  end

  defp audit_decision(decision, attrs, reason \\ nil) do
    :telemetry.execute(
      [:portfolio, :authz, :decision],
      %{count: 1},
      %{
        decision: decision,
        subject_id: attrs.subject.id,
        action: attrs.action,
        resource_type: attrs.resource.type,
        resource_id: attrs.resource.id,
        reason: reason
      }
    )
  end
end

defmodule PortfolioCore.Authz.PolicyEngine do
  @moduledoc """
  Policy Decision Point (PDP) - evaluates ABAC policies.
  """

  @type policy :: %{
    id: String.t(),
    effect: :permit | :deny,
    target: target_spec(),
    condition: condition_spec()
  }

  @doc """
  Evaluate policies against request attributes.
  Returns first matching policy result (deny takes precedence).
  """
  def evaluate(attrs) do
    policies = load_policies(attrs.resource.type)

    # Deny-override combining algorithm
    results = Enum.map(policies, &evaluate_policy(&1, attrs))

    cond do
      Enum.any?(results, &match?({:deny, _}, &1)) ->
        Enum.find(results, &match?({:deny, _}, &1))

      Enum.any?(results, &match?({:permit, _}, &1)) ->
        Enum.find(results, &match?({:permit, _}, &1))

      true ->
        {:not_applicable, :no_match}
    end
  end

  defp evaluate_policy(policy, attrs) do
    with true <- target_matches?(policy.target, attrs),
         true <- condition_holds?(policy.condition, attrs) do
      {policy.effect, policy.id}
    else
      false -> {:not_applicable, policy.id}
    end
  end

  defp target_matches?(%{actions: actions, resource_types: types}, attrs) do
    attrs.action in actions and attrs.resource.type in types
  end

  defp condition_holds?(nil, _attrs), do: true
  defp condition_holds?(condition, attrs) do
    ConditionEvaluator.evaluate(condition, attrs)
  end
end
```

### 3.2 Multi-Tenant Isolation

```elixir
defmodule PortfolioCore.Authz.TenantIsolation do
  @moduledoc """
  Ensures tenant isolation at query and data access layers.
  """

  import Ecto.Query

  @doc """
  Wraps query with tenant filter. MUST be applied to all queries.
  """
  def scope_to_tenant(query, tenant_id) when is_binary(tenant_id) do
    from q in query, where: q.tenant_id == ^tenant_id
  end

  @doc """
  Middleware for GraphQL resolvers.
  """
  def tenant_middleware(resolution, _config) do
    tenant_id = resolution.context[:tenant_id]

    if tenant_id do
      %{resolution | context: Map.put(resolution.context, :scoped_repo, scoped_repo(tenant_id))}
    else
      Absinthe.Resolution.put_result(resolution, {:error, "Tenant context required"})
    end
  end

  @doc """
  Creates a scoped repo module for tenant isolation.
  """
  def scoped_repo(tenant_id) do
    %__MODULE__.ScopedRepo{tenant_id: tenant_id}
  end

  defmodule ScopedRepo do
    defstruct [:tenant_id]

    def all(%__MODULE__{tenant_id: tid}, queryable) do
      queryable
      |> PortfolioCore.Authz.TenantIsolation.scope_to_tenant(tid)
      |> Repo.all()
    end

    def get(%__MODULE__{tenant_id: tid}, queryable, id) do
      result = queryable
      |> PortfolioCore.Authz.TenantIsolation.scope_to_tenant(tid)
      |> Repo.get(id)

      case result do
        nil -> {:error, :not_found}
        record -> {:ok, record}
      end
    end

    def insert(%__MODULE__{tenant_id: tid}, changeset) do
      changeset
      |> Ecto.Changeset.put_change(:tenant_id, tid)
      |> Repo.insert()
    end
  end
end

defmodule PortfolioCore.Authz.GraphIsolation do
  @moduledoc """
  Tenant isolation for graph queries (Neo4j/Cypher).
  """

  @doc """
  Wraps Cypher query with tenant property filter.
  """
  def scope_cypher(query, tenant_id) do
    # Inject tenant filter into MATCH clauses
    # This is a simplified version - production would use proper AST manipulation

    tenant_filter = "tenant_id: '#{sanitize(tenant_id)}'"

    query
    |> String.replace(~r/MATCH\s*\((\w+)\)/, "MATCH (\\1 {#{tenant_filter}})")
    |> String.replace(~r/MATCH\s*\((\w+):(\w+)\)/, "MATCH (\\1:\\2 {#{tenant_filter}})")
  end

  @doc """
  Validates query doesn't bypass tenant isolation.
  """
  def validate_query(query, tenant_id) do
    cond do
      # Check for tenant_id override attempts
      query =~ ~r/tenant_id\s*[:=]/ and not (query =~ tenant_id) ->
        {:error, :tenant_bypass_attempt}

      # Check for DETACH DELETE without tenant scope
      query =~ ~r/DETACH DELETE/i and not (query =~ ~r/WHERE.*tenant_id/i) ->
        {:error, :unsafe_delete}

      true ->
        :ok
    end
  end

  defp sanitize(value) when is_binary(value) do
    String.replace(value, ~r/[^a-zA-Z0-9_-]/, "")
  end
end
```

### 3.3 Row-Level Security

```sql
-- PostgreSQL Row-Level Security Policies

-- Enable RLS on all tables
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE embeddings ENABLE ROW LEVEL SECURITY;
ALTER TABLE graphs ENABLE ROW LEVEL SECURITY;
ALTER TABLE graph_nodes ENABLE ROW LEVEL SECURITY;

-- Application role for queries
CREATE ROLE portfolio_app;

-- Policy: Users can only see their tenant's data
CREATE POLICY tenant_isolation_documents ON documents
    FOR ALL
    TO portfolio_app
    USING (tenant_id = current_setting('app.tenant_id')::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);

CREATE POLICY tenant_isolation_chunks ON chunks
    FOR ALL
    TO portfolio_app
    USING (tenant_id = current_setting('app.tenant_id')::uuid)
    WITH CHECK (tenant_id = current_setting('app.tenant_id')::uuid);

-- Policy: Read-only access to public graphs
CREATE POLICY public_graph_read ON graphs
    FOR SELECT
    TO portfolio_app
    USING (
        tenant_id = current_setting('app.tenant_id')::uuid
        OR visibility = 'public'
    );

-- Function to set tenant context
CREATE OR REPLACE FUNCTION set_tenant_context(p_tenant_id UUID)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.tenant_id', p_tenant_id::text, true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

```elixir
defmodule PortfolioCore.Repo.TenantContext do
  @moduledoc """
  Sets PostgreSQL RLS context for tenant isolation.
  """

  import Ecto.Adapters.SQL

  def with_tenant(tenant_id, fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      # Set tenant context for RLS
      query!(Repo, "SELECT set_tenant_context($1)", [tenant_id])
      fun.()
    end)
  end

  def set_tenant(conn, tenant_id) do
    query!(conn, "SELECT set_tenant_context($1)", [tenant_id])
  end
end
```

---

## 4. Secrets Management

### 4.1 Secret Port Abstraction

```elixir
defmodule PortfolioCore.Secrets.Port do
  @moduledoc """
  Port for secrets management - abstracts secret storage backends.
  """

  @type secret_name :: String.t()
  @type secret_value :: String.t()
  @type secret_metadata :: %{
    version: String.t(),
    created_at: DateTime.t(),
    rotation_schedule: String.t() | nil
  }

  @callback get_secret(secret_name()) ::
    {:ok, secret_value(), secret_metadata()} | {:error, :not_found | :access_denied}

  @callback set_secret(secret_name(), secret_value(), opts :: keyword()) ::
    {:ok, secret_metadata()} | {:error, term()}

  @callback rotate_secret(secret_name()) ::
    {:ok, secret_value(), secret_metadata()} | {:error, term()}

  @callback list_secrets(prefix :: String.t()) :: [secret_name()]

  @callback delete_secret(secret_name()) :: :ok | {:error, term()}
end

defmodule PortfolioCore.Secrets.Vault.Adapter do
  @behaviour PortfolioCore.Secrets.Port

  @impl true
  def get_secret(name) do
    path = secret_path(name)

    case Vault.read(client(), path) do
      {:ok, %{"data" => %{"data" => data, "metadata" => meta}}} ->
        {:ok, data["value"], parse_metadata(meta)}

      {:error, %{"errors" => ["permission denied"]}} ->
        {:error, :access_denied}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @impl true
  def set_secret(name, value, opts) do
    path = secret_path(name)

    data = %{
      "data" => %{"value" => value},
      "options" => %{"cas" => opts[:cas] || 0}
    }

    case Vault.write(client(), path, data) do
      {:ok, %{"data" => meta}} -> {:ok, parse_metadata(meta)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def rotate_secret(name) do
    # Generate new secret value based on type
    case get_secret_type(name) do
      :api_key -> rotate_api_key(name)
      :database_password -> rotate_db_password(name)
      :encryption_key -> rotate_encryption_key(name)
      _ -> {:error, :unknown_secret_type}
    end
  end

  defp client do
    Vault.new(
      host: System.get_env("VAULT_ADDR"),
      auth: Vault.Auth.Kubernetes,
      credentials: %{role: "portfolio-app"}
    )
  end

  defp secret_path(name), do: "secret/data/portfolio/#{name}"
end

defmodule PortfolioCore.Secrets.Encrypted.Adapter do
  @behaviour PortfolioCore.Secrets.Port
  @moduledoc """
  Local encrypted secrets storage for development/small deployments.
  Uses envelope encryption with master key from environment.
  """

  alias PortfolioCore.Encryption

  @impl true
  def get_secret(name) do
    case Repo.get_by(EncryptedSecret, name: name) do
      nil ->
        {:error, :not_found}

      secret ->
        {:ok, decrypted} = Encryption.decrypt(secret.encrypted_value, secret.key_id)
        {:ok, decrypted, build_metadata(secret)}
    end
  end

  @impl true
  def set_secret(name, value, opts) do
    key_id = Encryption.current_key_id()
    {:ok, encrypted} = Encryption.encrypt(value, key_id)

    attrs = %{
      name: name,
      encrypted_value: encrypted,
      key_id: key_id,
      version: (opts[:version] || 1)
    }

    case Repo.insert(
      %EncryptedSecret{} |> EncryptedSecret.changeset(attrs),
      on_conflict: {:replace, [:encrypted_value, :key_id, :version, :updated_at]},
      conflict_target: :name
    ) do
      {:ok, secret} -> {:ok, build_metadata(secret)}
      error -> error
    end
  end
end
```

### 4.2 Encryption at Rest

```elixir
defmodule PortfolioCore.Encryption do
  @moduledoc """
  Envelope encryption for data at rest.
  Master key encrypts data keys, data keys encrypt data.
  """

  @aes_key_size 32  # 256-bit
  @nonce_size 12

  @doc """
  Encrypt data using envelope encryption.
  """
  def encrypt(plaintext, key_id \\ current_key_id()) do
    # Generate random data encryption key
    dek = :crypto.strong_rand_bytes(@aes_key_size)
    nonce = :crypto.strong_rand_bytes(@nonce_size)

    # Encrypt data with DEK
    {ciphertext, tag} = :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      dek,
      nonce,
      plaintext,
      _aad = key_id,
      true
    )

    # Encrypt DEK with master key (KEK)
    {:ok, kek} = get_master_key(key_id)
    encrypted_dek = :crypto.crypto_one_time(
      :aes_256_ecb,
      kek,
      dek,
      true
    )

    # Bundle: key_id | nonce | encrypted_dek | tag | ciphertext
    envelope = <<
      byte_size(key_id)::8,
      key_id::binary,
      nonce::binary-size(@nonce_size),
      encrypted_dek::binary-size(@aes_key_size),
      tag::binary-size(16),
      ciphertext::binary
    >>

    {:ok, Base.encode64(envelope)}
  end

  @doc """
  Decrypt envelope-encrypted data.
  """
  def decrypt(encoded, key_id \\ nil) do
    {:ok, envelope} = Base.decode64(encoded)

    <<
      key_id_size::8,
      actual_key_id::binary-size(key_id_size),
      nonce::binary-size(@nonce_size),
      encrypted_dek::binary-size(@aes_key_size),
      tag::binary-size(16),
      ciphertext::binary
    >> = envelope

    # Verify key_id if provided
    if key_id && key_id != actual_key_id do
      {:error, :key_mismatch}
    else
      # Decrypt DEK with master key
      {:ok, kek} = get_master_key(actual_key_id)
      dek = :crypto.crypto_one_time(:aes_256_ecb, kek, encrypted_dek, false)

      # Decrypt data with DEK
      case :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        dek,
        nonce,
        ciphertext,
        actual_key_id,
        tag,
        false
      ) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        :error -> {:error, :decryption_failed}
      end
    end
  end

  def current_key_id do
    Application.get_env(:portfolio_core, :current_encryption_key_id)
  end

  defp get_master_key(key_id) do
    # In production, retrieve from HSM or Vault
    case System.get_env("MASTER_KEY_#{key_id}") do
      nil -> {:error, :key_not_found}
      key -> {:ok, Base.decode64!(key)}
    end
  end
end
```

---

## 5. Audit Logging

### 5.1 Immutable Audit Log

```elixir
defmodule PortfolioCore.Audit.Port do
  @moduledoc """
  Audit logging port - immutable, tamper-evident logging.
  """

  @type event_type :: :auth | :authz | :data_access | :data_modify | :admin | :system
  @type severity :: :info | :warning | :error | :critical

  @type audit_event :: %{
    event_id: String.t(),
    event_type: event_type(),
    severity: severity(),
    timestamp: DateTime.t(),
    actor: actor_info(),
    action: String.t(),
    resource: resource_info(),
    outcome: :success | :failure,
    details: map(),
    request_context: request_context()
  }

  @type actor_info :: %{
    id: String.t(),
    type: :user | :service | :system,
    tenant_id: String.t() | nil,
    ip_address: String.t() | nil
  }

  @type resource_info :: %{
    type: String.t(),
    id: String.t() | nil,
    name: String.t() | nil
  }

  @type request_context :: %{
    request_id: String.t(),
    trace_id: String.t() | nil,
    user_agent: String.t() | nil
  }

  @callback log(audit_event()) :: {:ok, String.t()} | {:error, term()}
  @callback query(filters :: map(), opts :: keyword()) :: {:ok, [audit_event()]}
  @callback verify_integrity(from :: DateTime.t(), to :: DateTime.t()) :: :ok | {:error, term()}
end

defmodule PortfolioCore.Audit.ChainedLog.Adapter do
  @behaviour PortfolioCore.Audit.Port

  @moduledoc """
  Append-only audit log with hash chaining for tamper detection.
  Similar to blockchain - each entry includes hash of previous entry.
  """

  alias PortfolioCore.Audit.AuditEntry

  @impl true
  def log(event) do
    # Get hash of previous entry
    previous_hash = get_latest_hash(event.actor.tenant_id)

    # Create entry with chained hash
    entry = %AuditEntry{
      event_id: generate_event_id(),
      tenant_id: event.actor.tenant_id,
      event_type: event.event_type,
      severity: event.severity,
      timestamp: DateTime.utc_now(),
      actor: event.actor,
      action: event.action,
      resource: event.resource,
      outcome: event.outcome,
      details: event.details,
      request_context: event.request_context,
      previous_hash: previous_hash
    }

    # Compute hash including previous_hash
    entry = %{entry | entry_hash: compute_hash(entry)}

    # Sign for non-repudiation
    entry = %{entry | signature: sign_entry(entry)}

    case Repo.insert(entry) do
      {:ok, saved} -> {:ok, saved.event_id}
      error -> error
    end
  end

  @impl true
  def verify_integrity(from, to) do
    entries =
      AuditEntry
      |> where([e], e.timestamp >= ^from and e.timestamp <= ^to)
      |> order_by([e], asc: e.timestamp)
      |> Repo.all()

    verify_chain(entries)
  end

  defp verify_chain([]), do: :ok
  defp verify_chain([first | rest]) do
    verify_chain(rest, first.entry_hash, [first.event_id])
  end

  defp verify_chain([], _prev_hash, _verified), do: :ok
  defp verify_chain([entry | rest], expected_prev_hash, verified) do
    cond do
      entry.previous_hash != expected_prev_hash ->
        {:error, {:chain_broken, entry.event_id, verified}}

      compute_hash(entry) != entry.entry_hash ->
        {:error, {:tampered, entry.event_id}}

      not verify_signature(entry) ->
        {:error, {:invalid_signature, entry.event_id}}

      true ->
        verify_chain(rest, entry.entry_hash, [entry.event_id | verified])
    end
  end

  defp compute_hash(entry) do
    data = :erlang.term_to_binary(%{
      event_id: entry.event_id,
      timestamp: entry.timestamp,
      actor: entry.actor,
      action: entry.action,
      resource: entry.resource,
      outcome: entry.outcome,
      details: entry.details,
      previous_hash: entry.previous_hash
    })

    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp sign_entry(entry) do
    {:ok, key} = PortfolioCore.Auth.KeyRotation.signing_key()
    :public_key.sign(entry.entry_hash, :sha256, key) |> Base.encode64()
  end

  defp verify_signature(entry) do
    keys = PortfolioCore.Auth.KeyRotation.current_keys()
    signature = Base.decode64!(entry.signature)

    Enum.any?(keys, fn key ->
      :public_key.verify(entry.entry_hash, :sha256, signature, key)
    end)
  end

  defp generate_event_id do
    "aud_" <> Nanoid.generate(21)
  end
end
```

### 5.2 Audit Event Emission

```elixir
defmodule PortfolioCore.Audit.Emitter do
  @moduledoc """
  Convenience functions for emitting audit events.
  Integrates with telemetry for automatic emission.
  """

  alias PortfolioCore.Audit

  def emit_auth_event(action, actor, outcome, details \\ %{}) do
    Audit.log(%{
      event_type: :auth,
      severity: if(outcome == :success, do: :info, else: :warning),
      actor: actor,
      action: action,
      resource: %{type: "auth", id: nil, name: nil},
      outcome: outcome,
      details: details,
      request_context: current_request_context()
    })
  end

  def emit_data_access(action, actor, resource, details \\ %{}) do
    Audit.log(%{
      event_type: :data_access,
      severity: :info,
      actor: actor,
      action: action,
      resource: resource,
      outcome: :success,
      details: details,
      request_context: current_request_context()
    })
  end

  def emit_data_modify(action, actor, resource, outcome, details \\ %{}) do
    Audit.log(%{
      event_type: :data_modify,
      severity: if(outcome == :success, do: :info, else: :error),
      actor: actor,
      action: action,
      resource: resource,
      outcome: outcome,
      details: Map.merge(details, %{changes: details[:changes]}),
      request_context: current_request_context()
    })
  end

  def emit_security_event(action, actor, details) do
    Audit.log(%{
      event_type: :admin,
      severity: :warning,
      actor: actor,
      action: action,
      resource: %{type: "security", id: nil, name: nil},
      outcome: :success,
      details: details,
      request_context: current_request_context()
    })
  end

  defp current_request_context do
    case Process.get(:audit_context) do
      nil -> %{request_id: UUID.uuid4(), trace_id: nil, user_agent: nil}
      ctx -> ctx
    end
  end
end

# Telemetry handler for automatic audit logging
defmodule PortfolioCore.Audit.TelemetryHandler do
  def attach do
    :telemetry.attach_many(
      "portfolio-audit-handler",
      [
        [:portfolio, :auth, :login],
        [:portfolio, :auth, :logout],
        [:portfolio, :authz, :decision],
        [:portfolio, :document, :create],
        [:portfolio, :document, :update],
        [:portfolio, :document, :delete],
        [:portfolio, :query, :execute]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:portfolio, :auth, :login], _measurements, metadata, _config) do
    PortfolioCore.Audit.Emitter.emit_auth_event(
      "login",
      %{id: metadata.user_id, type: :user, tenant_id: metadata.tenant_id},
      metadata.outcome,
      %{method: metadata.method}
    )
  end

  def handle_event([:portfolio, :authz, :decision], _measurements, metadata, _config) do
    if metadata.decision == :deny do
      PortfolioCore.Audit.Emitter.emit_security_event(
        "authorization_denied",
        %{id: metadata.subject_id, type: :user, tenant_id: nil},
        %{
          action: metadata.action,
          resource_type: metadata.resource_type,
          reason: metadata.reason
        }
      )
    end
  end

  # ... other handlers
end
```

---

## 6. Observability Architecture

### 6.1 OpenTelemetry Integration

```elixir
defmodule PortfolioCore.Telemetry do
  @moduledoc """
  OpenTelemetry setup and custom instrumentation.
  """

  require OpenTelemetry.Tracer, as: Tracer

  def setup do
    # Configure exporters
    :opentelemetry.set_default_tracer(:portfolio_tracer)

    # Attach Phoenix/Ecto instrumentation
    :telemetry.attach_many(
      "portfolio-otel-handler",
      [
        [:phoenix, :endpoint, :start],
        [:phoenix, :endpoint, :stop],
        [:ecto, :repo, :query],
        [:broadway, :processor, :message, :start],
        [:broadway, :processor, :message, :stop]
      ],
      &handle_event/4,
      nil
    )
  end

  @doc """
  Wrap a function in a traced span.
  """
  defmacro with_span(name, attributes \\ %{}, do: block) do
    quote do
      Tracer.with_span unquote(name), %{attributes: unquote(attributes)} do
        try do
          result = unquote(block)
          Tracer.set_status(:ok)
          result
        rescue
          e ->
            Tracer.set_status(:error, Exception.message(e))
            Tracer.record_exception(e, __STACKTRACE__)
            reraise e, __STACKTRACE__
        end
      end
    end
  end

  @doc """
  Add attributes to current span.
  """
  def add_span_attributes(attrs) when is_map(attrs) do
    Tracer.set_attributes(Map.to_list(attrs))
  end

  @doc """
  Record a span event.
  """
  def add_span_event(name, attrs \\ %{}) do
    Tracer.add_event(name, Map.to_list(attrs))
  end

  # Telemetry handlers
  def handle_event([:phoenix, :endpoint, :start], _measurements, metadata, _config) do
    ctx = :otel_propagator_text_map.extract(metadata.conn.req_headers)
    Tracer.start_span("http.request", %{parent: ctx})

    Tracer.set_attributes([
      {"http.method", metadata.conn.method},
      {"http.target", metadata.conn.request_path},
      {"http.host", metadata.conn.host}
    ])
  end

  def handle_event([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
    Tracer.set_attributes([
      {"http.status_code", metadata.conn.status}
    ])

    if metadata.conn.status >= 500 do
      Tracer.set_status(:error, "HTTP #{metadata.conn.status}")
    end

    Tracer.end_span()
  end

  def handle_event([:ecto, :repo, :query], measurements, metadata, _config) do
    Tracer.with_span "db.query" do
      Tracer.set_attributes([
        {"db.system", "postgresql"},
        {"db.statement", metadata.query},
        {"db.operation", parse_operation(metadata.query)}
      ])

      if measurements.queue_time do
        Tracer.add_event("queue_time", [{"duration_ms", System.convert_time_unit(measurements.queue_time, :native, :millisecond)}])
      end
    end
  end

  def handle_event([:broadway, :processor, :message, :start], _measurements, metadata, _config) do
    Tracer.start_span("broadway.process", %{
      attributes: [
        {"messaging.system", "broadway"},
        {"messaging.destination", metadata.name}
      ]
    })
  end

  def handle_event([:broadway, :processor, :message, :stop], measurements, metadata, _config) do
    if metadata[:status] == :failed do
      Tracer.set_status(:error, "Message processing failed")
    end
    Tracer.end_span()
  end

  defp parse_operation(query) do
    query
    |> String.trim()
    |> String.split(" ", parts: 2)
    |> List.first()
    |> String.upcase()
  end
end
```

### 6.2 Custom Metrics

```elixir
defmodule PortfolioCore.Metrics do
  @moduledoc """
  Application metrics using Prometheus via :telemetry.
  """

  use Prometheus.PlugExporter

  def setup do
    # Counters
    :telemetry_metrics_prometheus.setup([
      Telemetry.Metrics.counter("portfolio.rag.queries.total",
        tags: [:tenant_id, :model, :strategy]
      ),
      Telemetry.Metrics.counter("portfolio.embeddings.total",
        tags: [:model, :status]
      ),
      Telemetry.Metrics.counter("portfolio.auth.attempts.total",
        tags: [:method, :outcome]
      ),

      # Histograms
      Telemetry.Metrics.distribution("portfolio.rag.query.duration",
        unit: :millisecond,
        tags: [:strategy],
        buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000]
      ),
      Telemetry.Metrics.distribution("portfolio.embedding.duration",
        unit: :millisecond,
        tags: [:model],
        buckets: [50, 100, 250, 500, 1000, 2500]
      ),
      Telemetry.Metrics.distribution("portfolio.graph.query.duration",
        unit: :millisecond,
        tags: [:graph_id, :query_type],
        buckets: [10, 50, 100, 250, 500, 1000]
      ),

      # Gauges
      Telemetry.Metrics.last_value("portfolio.vector.index.size",
        tags: [:index_id]
      ),
      Telemetry.Metrics.last_value("portfolio.graph.node.count",
        tags: [:graph_id]
      ),
      Telemetry.Metrics.last_value("portfolio.queue.depth",
        tags: [:queue_name]
      ),

      # Summaries for cost tracking
      Telemetry.Metrics.summary("portfolio.llm.tokens.total",
        tags: [:model, :type]  # type: input | output
      ),
      Telemetry.Metrics.summary("portfolio.llm.cost.dollars",
        tags: [:model]
      )
    ])
  end

  @doc """
  Emit RAG query metrics.
  """
  def record_rag_query(tenant_id, model, strategy, duration_ms) do
    :telemetry.execute(
      [:portfolio, :rag, :queries],
      %{total: 1, duration: duration_ms},
      %{tenant_id: tenant_id, model: model, strategy: strategy}
    )
  end

  @doc """
  Emit embedding metrics.
  """
  def record_embedding(model, status, duration_ms, token_count) do
    :telemetry.execute(
      [:portfolio, :embeddings],
      %{total: 1, duration: duration_ms, tokens: token_count},
      %{model: model, status: status}
    )
  end

  @doc """
  Emit LLM cost metrics.
  """
  def record_llm_usage(model, input_tokens, output_tokens) do
    cost = calculate_cost(model, input_tokens, output_tokens)

    :telemetry.execute(
      [:portfolio, :llm, :tokens],
      %{input: input_tokens, output: output_tokens},
      %{model: model}
    )

    :telemetry.execute(
      [:portfolio, :llm, :cost],
      %{dollars: cost},
      %{model: model}
    )
  end

  defp calculate_cost(model, input, output) do
    rates = %{
      "gpt-4" => {0.03 / 1000, 0.06 / 1000},
      "gpt-4-turbo" => {0.01 / 1000, 0.03 / 1000},
      "gpt-3.5-turbo" => {0.0005 / 1000, 0.0015 / 1000},
      "claude-3-opus" => {0.015 / 1000, 0.075 / 1000},
      "claude-3-sonnet" => {0.003 / 1000, 0.015 / 1000}
    }

    {input_rate, output_rate} = Map.get(rates, model, {0.001 / 1000, 0.002 / 1000})
    input * input_rate + output * output_rate
  end
end
```

### 6.3 Distributed Tracing Context

```elixir
defmodule PortfolioCore.Tracing.Propagation do
  @moduledoc """
  Trace context propagation across service boundaries.
  """

  @doc """
  Extract trace context from incoming request headers.
  """
  def extract_context(headers) when is_list(headers) do
    :otel_propagator_text_map.extract(headers)
  end

  @doc """
  Inject trace context into outgoing request headers.
  """
  def inject_context(headers \\ []) do
    :otel_propagator_text_map.inject(headers)
  end

  @doc """
  Create a linked span for async operations.
  """
  def create_async_span(name, parent_ctx) do
    OpenTelemetry.Tracer.start_span(name, %{
      links: [OpenTelemetry.link(parent_ctx)]
    })
  end

  @doc """
  Propagate context through Broadway pipeline.
  """
  def with_broadway_context(message, fun) do
    ctx = extract_from_message(message)
    OpenTelemetry.Ctx.attach(ctx)

    try do
      fun.()
    after
      OpenTelemetry.Ctx.detach(ctx)
    end
  end

  defp extract_from_message(%{metadata: %{trace_context: ctx}}), do: ctx
  defp extract_from_message(_), do: OpenTelemetry.Ctx.new()
end

defmodule PortfolioCore.Tracing.Baggage do
  @moduledoc """
  Request-scoped context propagation via baggage.
  """

  @doc """
  Set tenant context in baggage for cross-service propagation.
  """
  def set_tenant_baggage(tenant_id) do
    OpenTelemetry.Baggage.set("tenant_id", tenant_id)
  end

  @doc """
  Set user context in baggage.
  """
  def set_user_baggage(user_id) do
    OpenTelemetry.Baggage.set("user_id", user_id)
  end

  @doc """
  Get tenant from baggage.
  """
  def get_tenant do
    OpenTelemetry.Baggage.get("tenant_id")
  end

  @doc """
  Get user from baggage.
  """
  def get_user do
    OpenTelemetry.Baggage.get("user_id")
  end
end
```

### 6.4 Alerting Rules

```yaml
# prometheus/alerts.yml
groups:
  - name: portfolio_rag
    rules:
      - alert: HighRAGLatency
        expr: histogram_quantile(0.95, rate(portfolio_rag_query_duration_bucket[5m])) > 2000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "RAG query latency is high"
          description: "95th percentile latency is {{ $value }}ms"

      - alert: EmbeddingFailureRate
        expr: rate(portfolio_embeddings_total{status="error"}[5m]) / rate(portfolio_embeddings_total[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Embedding failure rate exceeds 5%"
          description: "Current failure rate: {{ $value | humanizePercentage }}"

      - alert: LLMCostSpike
        expr: increase(portfolio_llm_cost_dollars_sum[1h]) > 100
        labels:
          severity: warning
        annotations:
          summary: "LLM costs spiking"
          description: "Spent ${{ $value }} in the last hour"

      - alert: VectorIndexSizeGrowing
        expr: delta(portfolio_vector_index_size[1d]) / portfolio_vector_index_size > 0.2
        labels:
          severity: info
        annotations:
          summary: "Vector index growing rapidly"
          description: "Index {{ $labels.index_id }} grew by {{ $value | humanizePercentage }}"

  - name: portfolio_auth
    rules:
      - alert: AuthenticationFailures
        expr: rate(portfolio_auth_attempts_total{outcome="failure"}[5m]) > 10
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High authentication failure rate"
          description: "{{ $value }} failures per second"

      - alert: SuspiciousAuthPattern
        expr: |
          sum by (ip) (rate(portfolio_auth_attempts_total{outcome="failure"}[5m])) > 5
          and
          sum by (ip) (rate(portfolio_auth_attempts_total{outcome="success"}[5m])) < 1
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Possible brute force attack"
          description: "IP {{ $labels.ip }} has high failure rate with no successes"

  - name: portfolio_infrastructure
    rules:
      - alert: QueueDepthHigh
        expr: portfolio_queue_depth > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Queue depth is high"
          description: "Queue {{ $labels.queue_name }} has {{ $value }} items"

      - alert: GraphQuerySlow
        expr: histogram_quantile(0.99, rate(portfolio_graph_query_duration_bucket[5m])) > 1000
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "Graph queries are slow"
          description: "99th percentile: {{ $value }}ms for graph {{ $labels.graph_id }}"
```

---

## 7. Compliance & Data Governance

### 7.1 Data Classification

```elixir
defmodule PortfolioCore.Governance.Classification do
  @moduledoc """
  Data classification system for compliance.
  """

  @classifications %{
    public: %{
      level: 0,
      retention: :indefinite,
      encryption: :optional,
      audit: :minimal
    },
    internal: %{
      level: 1,
      retention: {:years, 7},
      encryption: :at_rest,
      audit: :standard
    },
    confidential: %{
      level: 2,
      retention: {:years, 10},
      encryption: :at_rest_and_transit,
      audit: :detailed
    },
    restricted: %{
      level: 3,
      retention: {:years, 10},
      encryption: :at_rest_and_transit,
      audit: :comprehensive,
      access_review: :quarterly
    },
    pii: %{
      level: 3,
      retention: {:days, 90},  # GDPR compliance
      encryption: :at_rest_and_transit,
      audit: :comprehensive,
      right_to_erasure: true
    }
  }

  def get_classification(type), do: Map.get(@classifications, type)

  def requires_encryption?(type) do
    case get_classification(type) do
      %{encryption: :optional} -> false
      _ -> true
    end
  end

  def audit_level(type) do
    get_classification(type)[:audit]
  end

  def retention_policy(type) do
    get_classification(type)[:retention]
  end
end

defmodule PortfolioCore.Governance.DataRetention do
  @moduledoc """
  Automated data retention enforcement.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.info("Starting data retention cleanup")

    cleanup_expired_data()
    schedule_cleanup()

    {:noreply, state}
  end

  defp cleanup_expired_data do
    # Delete documents past retention
    classifications = PortfolioCore.Governance.Classification.all()

    for {type, config} <- classifications, config.retention != :indefinite do
      {:years, years} = config.retention
      cutoff = DateTime.add(DateTime.utc_now(), -years * 365, :day)

      {deleted, _} =
        from(d in Document,
          where: d.classification == ^type and d.created_at < ^cutoff
        )
        |> Repo.delete_all()

      Logger.info("Deleted #{deleted} #{type} documents past retention")

      :telemetry.execute(
        [:portfolio, :governance, :retention_cleanup],
        %{deleted: deleted},
        %{classification: type}
      )
    end
  end

  defp schedule_cleanup do
    # Run daily at 3 AM
    Process.send_after(self(), :cleanup, next_3am())
  end

  defp next_3am do
    now = DateTime.utc_now()
    target = %{now | hour: 3, minute: 0, second: 0}

    if DateTime.compare(target, now) == :lt do
      DateTime.add(target, 1, :day)
    else
      target
    end
    |> DateTime.diff(now, :millisecond)
  end
end
```

### 7.2 GDPR Right to Erasure

```elixir
defmodule PortfolioCore.Governance.GDPR do
  @moduledoc """
  GDPR compliance utilities.
  """

  alias PortfolioCore.Audit

  @doc """
  Process right to erasure (right to be forgotten) request.
  """
  def process_erasure_request(user_id, opts \\ []) do
    # Log the request
    Audit.Emitter.emit_security_event(
      "gdpr_erasure_request",
      %{id: "system", type: :system, tenant_id: nil},
      %{user_id: user_id, requested_at: DateTime.utc_now()}
    )

    # Collect all user data
    data_locations = [
      {:documents, fn -> erase_documents(user_id) end},
      {:embeddings, fn -> erase_embeddings(user_id) end},
      {:graph_nodes, fn -> erase_graph_data(user_id) end},
      {:audit_logs, fn -> anonymize_audit_logs(user_id) end},
      {:user_profile, fn -> delete_user_profile(user_id) end}
    ]

    results = Enum.map(data_locations, fn {location, erase_fn} ->
      try do
        {deleted, _} = erase_fn.()
        {:ok, location, deleted}
      rescue
        e -> {:error, location, Exception.message(e)}
      end
    end)

    # Generate erasure report
    report = generate_erasure_report(user_id, results)

    # Log completion
    Audit.Emitter.emit_security_event(
      "gdpr_erasure_completed",
      %{id: "system", type: :system, tenant_id: nil},
      %{user_id: user_id, report: report}
    )

    if opts[:return_report] do
      {:ok, report}
    else
      :ok
    end
  end

  defp erase_documents(user_id) do
    from(d in Document, where: d.owner_id == ^user_id)
    |> Repo.delete_all()
  end

  defp erase_embeddings(user_id) do
    # Delete from vector store
    VectorStore.delete_by_metadata(%{"owner_id" => user_id})
  end

  defp erase_graph_data(user_id) do
    # Remove user nodes and relationships from all graphs
    query = """
    MATCH (n {owner_id: $user_id})
    DETACH DELETE n
    """
    GraphStore.execute(query, %{user_id: user_id})
  end

  defp anonymize_audit_logs(user_id) do
    # We can't delete audit logs (compliance), but we anonymize
    from(a in AuditEntry, where: fragment("actor->>'id' = ?", ^user_id))
    |> Repo.update_all(set: [
      actor: %{id: "REDACTED", type: :user, tenant_id: nil}
    ])
  end

  defp delete_user_profile(user_id) do
    Repo.delete_all(from(u in User, where: u.id == ^user_id))
  end

  defp generate_erasure_report(user_id, results) do
    %{
      request_id: UUID.uuid4(),
      user_id: user_id,
      processed_at: DateTime.utc_now(),
      locations: Enum.map(results, fn
        {:ok, location, count} -> %{location: location, status: :erased, count: count}
        {:error, location, reason} -> %{location: location, status: :failed, reason: reason}
      end),
      certification: "Data erasure completed in accordance with GDPR Article 17"
    }
  end
end
```

---

## 8. Network Security

### 8.1 Service Mesh Configuration

```yaml
# istio/virtual-service.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: portfolio-api
spec:
  hosts:
    - portfolio-api
  http:
    - match:
        - headers:
            x-tenant-id:
              regex: "^[a-f0-9-]{36}$"
      route:
        - destination:
            host: portfolio-api
            port:
              number: 8080
      retries:
        attempts: 3
        perTryTimeout: 2s
        retryOn: "5xx,reset,connect-failure"
    - match:
        - uri:
            prefix: "/health"
      route:
        - destination:
            host: portfolio-api
---
# Mutual TLS for service-to-service
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: portfolio-mtls
spec:
  selector:
    matchLabels:
      app: portfolio
  mtls:
    mode: STRICT
---
# Authorization policy
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: portfolio-authz
spec:
  selector:
    matchLabels:
      app: portfolio-api
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/portfolio/sa/portfolio-gateway"]
      to:
        - operation:
            methods: ["GET", "POST", "PUT", "DELETE"]
            paths: ["/api/*"]
    - from:
        - source:
            principals: ["cluster.local/ns/portfolio/sa/portfolio-worker"]
      to:
        - operation:
            methods: ["POST"]
            paths: ["/internal/*"]
```

### 8.2 Rate Limiting

```elixir
defmodule PortfolioCore.RateLimit do
  @moduledoc """
  Distributed rate limiting using token bucket algorithm.
  """

  @doc """
  Check if request is allowed under rate limit.
  """
  def check(key, limit, window_ms) do
    now = System.system_time(:millisecond)
    bucket_key = "rate:#{key}"

    case Redix.pipeline!(:rate_limiter, [
      ["MULTI"],
      ["GET", bucket_key],
      ["PTTL", bucket_key],
      ["EXEC"]
    ]) do
      [_, _, _, [current, ttl]] ->
        current = parse_int(current)

        cond do
          current >= limit ->
            {:deny, %{limit: limit, remaining: 0, reset_in: ttl}}

          true ->
            Redix.command!(:rate_limiter, ["INCR", bucket_key])
            if ttl < 0, do: Redix.command!(:rate_limiter, ["PEXPIRE", bucket_key, window_ms])
            {:allow, %{limit: limit, remaining: limit - current - 1, reset_in: ttl}}
        end
    end
  end

  @doc """
  Apply tiered rate limits based on plan.
  """
  def check_tiered(tenant_id, endpoint) do
    plan = get_tenant_plan(tenant_id)
    limits = plan_limits(plan, endpoint)

    with {:allow, _} <- check("#{tenant_id}:#{endpoint}:sec", limits.per_second, 1000),
         {:allow, _} <- check("#{tenant_id}:#{endpoint}:min", limits.per_minute, 60_000),
         {:allow, info} <- check("#{tenant_id}:#{endpoint}:day", limits.per_day, 86_400_000) do
      {:allow, info}
    else
      {:deny, info} -> {:deny, info}
    end
  end

  defp plan_limits(:free, :rag_query), do: %{per_second: 1, per_minute: 20, per_day: 100}
  defp plan_limits(:pro, :rag_query), do: %{per_second: 10, per_minute: 200, per_day: 5000}
  defp plan_limits(:enterprise, :rag_query), do: %{per_second: 100, per_minute: 2000, per_day: 100_000}

  defp plan_limits(:free, :embedding), do: %{per_second: 5, per_minute: 100, per_day: 1000}
  defp plan_limits(:pro, :embedding), do: %{per_second: 50, per_minute: 1000, per_day: 50_000}
  defp plan_limits(:enterprise, :embedding), do: %{per_second: 500, per_minute: 10_000, per_day: 1_000_000}

  defp parse_int(nil), do: 0
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
  defp parse_int(val) when is_integer(val), do: val
end
```

---

## 9. Summary: Security Checklist

### Pre-Production Security Review

```markdown
## Authentication
- [ ] JWT tokens have short expiration (15 min access, 7d refresh)
- [ ] API keys are hashed with SHA-256, prefixed for identification
- [ ] Key rotation is automated with overlap period
- [ ] Mutual TLS enabled for service-to-service
- [ ] OIDC integration tested with all providers

## Authorization
- [ ] ABAC policies cover all resource types
- [ ] Deny-override combining algorithm in place
- [ ] Tenant isolation verified at query layer
- [ ] Row-level security enabled in PostgreSQL
- [ ] Graph queries scoped to tenant

## Data Security
- [ ] All PII encrypted at rest
- [ ] Envelope encryption with KEK rotation
- [ ] Secrets stored in Vault/KMS, not env vars
- [ ] No secrets in logs or error messages
- [ ] Backup encryption verified

## Audit & Compliance
- [ ] Immutable audit log with hash chaining
- [ ] Audit events signed for non-repudiation
- [ ] Retention policies automated
- [ ] GDPR erasure workflow tested
- [ ] Data classification applied to all tables

## Network
- [ ] mTLS between all services
- [ ] Rate limiting per tenant/endpoint
- [ ] WAF rules for common attacks
- [ ] DDoS protection enabled
- [ ] Egress filtering for external APIs

## Observability
- [ ] OpenTelemetry traces for all operations
- [ ] Security-relevant metrics collected
- [ ] Alerting rules for anomalies
- [ ] Cost tracking for LLM usage
- [ ] Log aggregation with 90-day retention
```

---

This security and observability architecture provides enterprise-grade protection for the RAG ecosystem while maintaining the flexibility needed for multi-tenant, multi-graph deployments. The combination of defense-in-depth security controls, comprehensive audit logging, and deep observability ensures both security and operational excellence.
