defmodule RiakTui.Client do
  @moduledoc """
  HTTP client for the Riak Admin API.

  All requests go to a base URL passed as an option or fall back to the default.
  Every function returns `{:ok, decoded_body}` on success or `{:error, reason}`
  on failure. JSON decoding is handled automatically by Req.
  """

  @default_url "http://127.0.0.1:10015"
  @default_timeout 5_000

  @type url_opt :: {:url, String.t()}
  @type opts :: [url_opt()]
  @type ok_or_error :: {:ok, map()} | {:error, term()}

  @doc "Fetches the current cluster status (members, ring size, claimant, pending changes)."
  @spec cluster_status(opts()) :: ok_or_error()
  def cluster_status(opts \\ []) do
    get(url(opts), "/api/cluster/status")
  end

  @doc "Lists all known datacenters discovered via the coordinator registry."
  @spec list_dcs(opts()) :: ok_or_error()
  def list_dcs(opts \\ []) do
    get(url(opts), "/api/dcs")
  end

  @doc "Fetches the full partition-to-node ring ownership map."
  @spec ring_ownership(opts()) :: ok_or_error()
  def ring_ownership(opts \\ []) do
    get(url(opts), "/api/ring/ownership")
  end

  @doc "Fetches VM and KV stats for a specific node."
  @spec node_stats(String.t(), opts()) :: ok_or_error()
  def node_stats(node_name, opts \\ []) do
    get(url(opts), "/api/nodes/#{URI.encode_www_form(node_name)}/stats")
  end

  @doc "Fetches the current handoff transfer status."
  @spec handoff_status(opts()) :: ok_or_error()
  def handoff_status(opts \\ []) do
    get(url(opts), "/api/handoff/status")
  end

  @doc "Health-check ping. Returns the node name and status."
  @spec ping(opts()) :: ok_or_error()
  def ping(opts \\ []) do
    get(url(opts), "/api/ping")
  end

  @doc "Fetches Active Anti-Entropy (AAE) exchange status."
  @spec aae_status(opts()) :: ok_or_error()
  def aae_status(opts \\ []) do
    get(url(opts), "/api/aae/status")
  end

  # --- Helpers ---

  @spec url(opts()) :: String.t()
  defp url(opts), do: Keyword.get(opts, :url, bootstrap_url())

  @spec get(String.t(), String.t()) :: ok_or_error()
  defp get(base_url, path) do
    case Req.get("#{base_url}#{path}", receive_timeout: timeout(), retry: false) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, {:transport, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec bootstrap_url() :: String.t()
  defp bootstrap_url do
    Application.get_env(:riak_tui, :bootstrap_url, @default_url)
    |> normalize_url()
  end

  @spec timeout() :: pos_integer()
  defp timeout do
    Application.get_env(:riak_tui, :http_timeout, @default_timeout)
    |> normalize_timeout()
  end

  @spec normalize_url(term()) :: String.t()
  defp normalize_url(url) when is_binary(url) do
    parsed = URI.parse(String.trim(url))

    if parsed.scheme in ["http", "https"] and is_binary(parsed.host) do
      String.trim(url)
    else
      @default_url
    end
  end

  defp normalize_url(_url), do: @default_url

  @spec normalize_timeout(term()) :: pos_integer()
  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp normalize_timeout(_timeout), do: @default_timeout
end
