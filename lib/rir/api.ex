defmodule Rir.Api do
  @moduledoc """
  Functions that update a given context with datasets by querying the RIPEstat API

  Notes:
  - AS nrs are strings, without the AS prefix, e.g. AS42 -> "42"
  - API call results are gathered in a map:
    ctx[:api_name] -> %{ resource => %{call: call, data: data}}
  - interpretation of data depends on :api_name

  """

  alias Rir.Stat

  # Helpers

  @spec decode(map) :: map
  defp decode(%{data: data, call: %{name: "announced-prefixes", status: :ok}}) do
    # Announced-prefixes is a list of prefixes
    %{prefixes: data["prefixes"] |> Enum.map(&Map.get(&1, "prefix"))}
  end

  defp decode(%{data: data, call: %{name: "as-routing-consistency", status: :ok} = _call}) do
    # notes
    # - irr_sources is a "-" and not a list, if the prefix is not in whois
    # AS-routing-consistency
    #   peers => %{peer => {:imports, bgp?, whois?, :exports, bgp?, whois?}}
    #   prefixes => %{prefix => {bgp?, whois?, authorities}
    prefixes = map_tuples(data["prefixes"], ["prefix", "in_bgp", "in_whois", "irr_sources"])
    exports = map_tuples(data["exports"], ["peer", "in_bgp", "in_whois"])
    imports = map_tuples(data["imports"], ["peer", "in_bgp", "in_whois"])

    peers =
      Map.merge(imports, exports, fn _peer, {a, b}, {c, d} -> {:imports, a, b, :exports, c, d} end)

    %{prefixes: prefixes, peers: peers}
  end

  defp decode(%{data: data, call: %{name: "as-overview", status: :ok}}) do
    data
  end

  defp decode(%{data: data, call: %{name: "network-info", status: :ok}}) do
    asn = data["asns"] |> List.first()
    %{asn: asn, asns: data["asns"], prefix: data["prefix"]}
  end

  defp decode(%{data: data, call: %{name: "rpki-validation", status: :ok} = _call}) do
    # Rpki-validation
    with status <- data["status"],
         roas <- data["validating_roas"] do
      %{
        status: Stat.to_atom(status),
        roas: list_tuples(roas, ["origin", "prefix", "max_length", "validity"])
      }
    end
  end

  defp decode(%{data: data, call: %{name: "whois", status: :ok}}) do
    # Whois
    records = Enum.map(data["records"], fn l -> list_tuples(l, ["key", "value"]) end)
    irr = Enum.map(data["irr_records"], fn l -> list_tuples(l, ["key", "value"]) end)

    %{
      autorities: data["authorities"],
      records: records,
      irr: irr
    }
  end

  defp decode(%{data: _data, call: %{name: name, status: :ok} = call}),
    # api endpoint has no decoder
    do: %{call: call, error: "missing Rir.Api.decode/2 for api endpoint #{inspect(name)}"}

  defp decode(%{error: reason, call: call}),
    # api returned an error response
    do: %{error: reason, call: call}

  defp decode(%{error: reason, url: url}),
    # api call itself failed
    do: %{error: reason, url: url}

  defp list_tuples(list, keys) do
    # turn a list of maps, into a list of tuples for selected keys
    list
    |> Enum.map(fn m -> for(k <- keys, do: Map.get(m, k)) end)
    |> Enum.map(fn l -> List.to_tuple(l) end)
  end

  defp map_tuples(list, [primary | keys]) do
    # turn a list of maps, into a map of tuples
    # - primary is the unique key, different for each map
    # - keys is the list of keys whose values are presented as a tuple
    list
    |> Enum.map(fn m -> {Map.get(m, primary), for(key <- keys, do: Map.get(m, key))} end)
    |> Enum.map(fn {k, l} -> {k, List.to_tuple(l)} end)
    |> Enum.into(%{})
  end

  defp store(data, ctx, api_call, resource) do
    # store resulting data in context under resource for given API endpoint name
    Map.get(ctx, api_call, %{})
    |> Map.put(resource, data)
    |> then(fn updated -> Map.put(ctx, api_call, updated) end)
  end

  # API

  def announced(ctx, asn) do
    Stat.url("announced-prefixes", resource: asn)
    |> Stat.get()
    |> decode()
    |> store(ctx, :announced, asn)
  end

  def as_overview(ctx, asn) do
    Stat.url("as-overview", resource: asn)
    |> Stat.get()
    |> decode()
    |> store(ctx, :as_overview, asn)
  end

  def consistency(ctx, asn) do
    Stat.url("as-routing-consistency", resource: asn)
    |> Stat.get()
    |> decode()
    |> store(ctx, :consistency, asn)
  end

  def network(ctx, prefix) do
    Stat.url("network-info", resource: prefix)
    |> Stat.get()
    |> decode()
    |> store(ctx, :network, prefix)
  end

  def roa(ctx, asn, prefix) do
    Stat.url("rpki-validation", resource: asn, prefix: prefix)
    |> Stat.get()
    |> decode()
    |> store(ctx, :roa, {asn, prefix})
  end

  def whois(ctx, resource) do
    Stat.url("whois", resource: resource)
    |> Stat.get()
    |> decode()
    |> store(ctx, :whois, resource)
  end
end
